// Minimal Firestore REST client + the money ledger.
// The Worker authenticates as a service account, so it bypasses security
// rules. It is the ONLY writer of `balanceKobo` and of non-cash transactions.

import { SignJWT, importPKCS8 } from 'jose';
import { HttpError } from './util.js';

let tokenCache = null;

async function accessToken(env) {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 60_000) return tokenCache.token;
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const key = await importPKCS8(sa.private_key, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/datastore' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error('Could not authenticate with Firebase');
  tokenCache = { token: data.access_token, expiresAt: Date.now() + (data.expires_in || 3600) * 1000 };
  return tokenCache.token;
}

export function resetTokenCache() {
  tokenCache = null;
}

// ---------- value encoding ----------

export function encodeValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields(v) } };
  return { stringValue: String(v) };
}

export function encodeFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = encodeValue(v);
  return out;
}

export function decodeValue(v) {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('stringValue' in v) return v.stringValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  return null;
}

export function decodeFields(fields = {}) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

// ---------- low-level calls ----------

const root = (env) => `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
const docName = (env, path) => `${root(env)}/${path}`;
const api = 'https://firestore.googleapis.com/v1/';

class FirestoreError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export async function getDoc(env, path) {
  const res = await fetch(api + docName(env, path), {
    headers: { authorization: `Bearer ${await accessToken(env)}` },
  });
  if (res.status === 404) return null;
  const body = await res.json();
  if (!res.ok) throw new FirestoreError(res.status, body?.error?.status, body?.error?.message);
  return { data: decodeFields(body.fields), updateTime: body.updateTime };
}

async function commit(env, writes) {
  const res = await fetch(`${api}${root(env)}:commit`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${await accessToken(env)}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });
  if (res.ok) return;
  const body = await res.json().catch(() => ({}));
  throw new FirestoreError(res.status, body?.error?.status, body?.error?.message || 'Firestore error');
}

const isConflict = (e) =>
  e instanceof FirestoreError &&
  (e.code === 'FAILED_PRECONDITION' || e.code === 'ABORTED' || e.code === 'ALREADY_EXISTS');

const userPath = (uid) => `users/${uid}`;
const txPath = (uid, id) => `users/${uid}/transactions/${id}`;

function incrementBalance(env, uid, kobo) {
  // Upsert the user doc (empty mask touches no fields) and add to the balance.
  return {
    update: { name: docName(env, userPath(uid)), fields: {} },
    updateMask: { fieldPaths: [] },
    updateTransforms: [{ fieldPath: 'balanceKobo', increment: { integerValue: String(kobo) } }],
  };
}

export async function setDoc(env, path, data) {
  await commit(env, [{ update: { name: docName(env, path), fields: encodeFields(data) } }]);
}

export async function mergeDoc(env, path, data) {
  await commit(env, [
    {
      update: { name: docName(env, path), fields: encodeFields(data) },
      updateMask: { fieldPaths: Object.keys(data) },
    },
  ]);
}

// ---------- ledger ----------

/**
 * Credit a merchant's float exactly once. The transaction document ID is the
 * idempotency key: a second call with the same txId is a no-op.
 * Returns true if the credit was applied, false if it had already happened.
 */
export async function credit(env, { uid, txId, kobo, tx }) {
  try {
    await commit(env, [
      {
        update: { name: docName(env, txPath(uid, txId)), fields: encodeFields(tx) },
        currentDocument: { exists: false },
      },
      incrementBalance(env, uid, kobo),
    ]);
    return true;
  } catch (e) {
    if (isConflict(e)) return false;
    throw e;
  }
}

/**
 * Take money from the float and create the transaction in one atomic commit.
 * Uses optimistic concurrency on the user document so two simultaneous
 * payments can never overdraw the balance.
 */
export async function debit(env, { uid, txId, kobo, tx }) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const user = await getDoc(env, userPath(uid));
    const balance = user?.data?.balanceKobo || 0;
    if (!user || balance < kobo) {
      throw new HttpError(402, 'Not enough float balance. Top up and try again.');
    }
    try {
      await commit(env, [
        {
          update: {
            name: docName(env, userPath(uid)),
            fields: encodeFields({ balanceKobo: balance - kobo }),
          },
          updateMask: { fieldPaths: ['balanceKobo'] },
          currentDocument: { updateTime: user.updateTime },
        },
        {
          update: { name: docName(env, txPath(uid, txId)), fields: encodeFields(tx) },
          currentDocument: { exists: false },
        },
      ]);
      return balance - kobo;
    } catch (e) {
      if (!isConflict(e)) throw e;
    }
  }
  throw new HttpError(409, 'Your balance changed while paying. Please try again.');
}

export async function getTx(env, uid, txId) {
  return getDoc(env, txPath(uid, txId));
}

/**
 * Move a pending transaction to a final state. If `refundKobo` is set the
 * money goes back to the float in the same commit. Only ever acts on a
 * transaction that is still pending, so it is safe to call more than once.
 */
export async function settleTx(env, { uid, txId, status, patch = {}, refundKobo = 0 }) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const tx = await getDoc(env, txPath(uid, txId));
    if (!tx) throw new HttpError(404, 'Transaction not found');
    if (tx.data.status !== 'pending') return tx.data.status;
    const fields = { status, ...patch };
    const writes = [
      {
        update: { name: docName(env, txPath(uid, txId)), fields: encodeFields(fields) },
        updateMask: { fieldPaths: Object.keys(fields) },
        currentDocument: { updateTime: tx.updateTime },
      },
    ];
    if (refundKobo > 0) writes.push(incrementBalance(env, uid, refundKobo));
    try {
      await commit(env, writes);
      return status;
    } catch (e) {
      if (!isConflict(e)) throw e;
    }
  }
  throw new HttpError(409, 'Could not update the transaction. Please try again.');
}
