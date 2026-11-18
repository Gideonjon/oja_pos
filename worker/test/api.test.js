// Run with: npm test
// Exercises the Worker end to end against in-memory fakes of Firestore,
// Paystack and VTpass (no network, no real keys).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';

import { createApp } from '../src/index.js';
import { resetTokenCache, encodeFields, decodeFields } from '../src/firestore.js';
import { lagosRequestId, hmacSha512Hex } from '../src/util.js';
import { interpret } from '../src/vtpass.js';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const env = {
  FIREBASE_PROJECT_ID: 'demo',
  VTPASS_BASE_URL: 'https://sandbox.vtpass.com/api',
  VTPASS_API_KEY: 'k',
  VTPASS_PUBLIC_KEY: 'PK',
  VTPASS_SECRET_KEY: 'SK',
  PAYSTACK_SECRET_KEY: 'sk_test_x',
  FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
    client_email: 'svc@demo.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  }),
};

const ROOT = 'projects/demo/databases/(default)/documents/';
let docs; // name -> { fields, updateTime }
let clock;
let paystackTx; // reference -> verify data
let vtpassPay; // (body) => response, or throws
let vtpassRequery;
let vtpassCalls;

const res = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

function fakeCommit({ writes }) {
  // Check every precondition first, then apply: all or nothing.
  for (const w of writes) {
    const cur = docs.get(w.update.name);
    const pre = w.currentDocument || {};
    if (pre.exists === false && cur) return res({ error: { status: 'ALREADY_EXISTS' } }, 409);
    if (pre.updateTime && (!cur || cur.updateTime !== pre.updateTime)) {
      return res({ error: { status: 'FAILED_PRECONDITION' } }, 400);
    }
  }
  for (const w of writes) {
    const cur = docs.get(w.update.name);
    let fields;
    if (w.updateMask) {
      fields = { ...(cur?.fields || {}) };
      for (const p of w.updateMask.fieldPaths) fields[p] = w.update.fields[p];
    } else {
      fields = { ...w.update.fields };
    }
    for (const t of w.updateTransforms || []) {
      const old = Number(fields[t.fieldPath]?.integerValue || 0);
      fields[t.fieldPath] = { integerValue: String(old + Number(t.increment.integerValue)) };
    }
    docs.set(w.update.name, { fields, updateTime: `t${++clock}` });
  }
  return res({});
}

globalThis.fetch = async (input, init = {}) => {
  const url = String(input);
  const body = init.body && typeof init.body === 'string' ? JSON.parse(init.body) : null;
  if (url.startsWith('https://oauth2.googleapis.com/token')) {
    return res({ access_token: 'tok', expires_in: 3600 });
  }
  if (url.startsWith('https://firestore.googleapis.com/v1/')) {
    const path = decodeURIComponent(url.slice('https://firestore.googleapis.com/v1/'.length));
    if (path.endsWith(':commit')) return fakeCommit(body);
    const doc = docs.get(path);
    return doc ? res({ name: path, ...doc }) : res({ error: { status: 'NOT_FOUND' } }, 404);
  }
  if (url === 'https://api.paystack.co/transaction/initialize') {
    paystackTx.set(body.reference, { status: 'abandoned', amount: body.amount, currency: 'NGN' });
    return res({ status: true, data: { authorization_url: 'https://checkout.paystack.com/abc', access_code: 'abc' } });
  }
  if (url.startsWith('https://api.paystack.co/transaction/verify/')) {
    const data = paystackTx.get(url.split('/').pop());
    return data ? res({ status: true, data }) : res({ status: false, message: 'not found' }, 404);
  }
  if (url.startsWith('https://sandbox.vtpass.com/api/service-variations')) {
    assert.equal(init.headers['public-key'], 'PK');
    return res({ content: { varations: [{ variation_code: 'mtn-1gb', name: '1GB', variation_amount: '1000.00' }] } });
  }
  if (url === 'https://sandbox.vtpass.com/api/pay') {
    assert.equal(init.headers['secret-key'], 'SK');
    vtpassCalls.push(body);
    return res(vtpassPay(body));
  }
  if (url === 'https://sandbox.vtpass.com/api/requery') return res(vtpassRequery(body));
  throw new Error(`Unexpected fetch: ${url}`);
};

const app = createApp({
  verifyUser: async (request) => {
    const uid = request.headers.get('x-test-uid');
    if (!uid) throw Object.assign(new Error('nope'), { status: 401 });
    return { uid, email: `${uid}@test.dev` };
  },
});

async function call(method, path, body, uid = 'alice', headers = {}) {
  const response = await app.fetch(
    new Request(`https://api.test${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...(uid ? { 'x-test-uid': uid } : {}), ...headers },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    }),
    env,
  );
  return { status: response.status, body: await response.json() };
}

const read = (name) => (docs.has(name) ? decodeFields(docs.get(name).fields) : undefined);
const user = (uid = 'alice') => read(`${ROOT}users/${uid}`);
const tx = (id, uid = 'alice') => read(`${ROOT}users/${uid}/transactions/${id}`);
const setBalance = (kobo, uid = 'alice') =>
  docs.set(`${ROOT}users/${uid}`, { fields: encodeFields({ balanceKobo: kobo, businessName: 'Shop' }), updateTime: `t${++clock}` });

beforeEach(() => {
  docs = new Map();
  clock = 0;
  paystackTx = new Map();
  vtpassCalls = [];
  vtpassPay = () => ({ code: '000', content: { transactions: { status: 'delivered' } } });
  vtpassRequery = () => ({ code: '099' });
  resetTokenCache();
});

test('request id starts with Lagos time (UTC+1)', () => {
  const id = lagosRequestId(new Date('2026-12-31T23:30:00Z'), 'abc');
  assert.equal(id, '202701010030abc');
});

test('vtpass interpret never calls an ambiguous answer a failure', () => {
  assert.equal(interpret({ code: '000', content: { transactions: { status: 'delivered' } } }).outcome, 'success');
  assert.equal(interpret({ code: '000', content: { transactions: { status: 'pending' } } }).outcome, 'pending');
  assert.equal(interpret({ code: '099' }).outcome, 'pending');
  assert.equal(interpret({ code: '016' }).outcome, 'failed');
  assert.equal(interpret({ code: '999' }).outcome, 'pending');
  assert.equal(interpret(undefined).outcome, 'pending');
});

test('protected routes reject requests without a user', async () => {
  const r = await call('POST', '/bills/pay', {}, null);
  assert.notEqual(r.status, 200);
});

test('paystack: pending until paid, then credited exactly once', async () => {
  const init = await call('POST', '/paystack/initialize', { amount: 2500, purpose: 'sale', note: 'Rice' });
  assert.equal(init.status, 200);
  const { reference } = init.body;

  let v = await call('POST', '/paystack/verify', { reference });
  assert.equal(v.body.status, 'pending');
  assert.equal(user(), undefined);

  paystackTx.set(reference, { status: 'success', amount: 250000, currency: 'NGN', channel: 'card' });
  v = await call('POST', '/paystack/verify', { reference });
  assert.equal(v.body.status, 'success');
  assert.equal(user().balanceKobo, 250000);
  assert.equal(tx(reference).type, 'sale');
  assert.equal(tx(reference).method, 'paystack');

  // Verifying again, or the webhook arriving late, must not credit twice.
  await call('POST', '/paystack/verify', { reference });
  const raw = JSON.stringify({ event: 'charge.success', data: { reference } });
  const sig = await hmacSha512Hex(env.PAYSTACK_SECRET_KEY, raw);
  const hook = await call('POST', '/paystack/webhook', raw, null, { 'x-paystack-signature': sig });
  assert.equal(hook.status, 200);
  assert.equal(user().balanceKobo, 250000);
});

test('paystack: webhook alone credits, bad signature is rejected', async () => {
  const { body } = await call('POST', '/paystack/initialize', { amount: 1000, purpose: 'topup' });
  paystackTx.set(body.reference, { status: 'success', amount: 100000, currency: 'NGN' });
  const raw = JSON.stringify({ event: 'charge.success', data: { reference: body.reference } });

  const bad = await call('POST', '/paystack/webhook', raw, null, { 'x-paystack-signature': 'deadbeef' });
  assert.equal(bad.status, 401);
  assert.equal(user(), undefined);

  const sig = await hmacSha512Hex(env.PAYSTACK_SECRET_KEY, raw);
  await call('POST', '/paystack/webhook', raw, null, { 'x-paystack-signature': sig });
  assert.equal(user().balanceKobo, 100000);
  assert.equal(tx(body.reference).type, 'topup');
});

test('paystack: another merchant cannot claim a reference; amount mismatch is not credited', async () => {
  const { body } = await call('POST', '/paystack/initialize', { amount: 1000 });
  paystackTx.set(body.reference, { status: 'success', amount: 100, currency: 'NGN' });
  assert.equal((await call('POST', '/paystack/verify', { reference: body.reference }, 'mallory')).status, 404);
  assert.equal((await call('POST', '/paystack/verify', { reference: body.reference })).status, 409);
  assert.equal(user(), undefined);
});

test('bills: airtime success debits the float', async () => {
  setBalance(100000);
  const r = await call('POST', '/bills/pay', { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 500 });
  assert.equal(r.status, 200);
  assert.equal(r.body.status, 'success');
  assert.equal(user().balanceKobo, 50000);
  assert.equal(user().businessName, 'Shop'); // other fields untouched
  assert.equal(tx(r.body.id).status, 'success');
  assert.match(vtpassCalls[0].request_id, /^\d{12}[a-z0-9]{12}$/);
});

test('bills: insufficient float never reaches VTpass', async () => {
  setBalance(10000);
  const r = await call('POST', '/bills/pay', { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 500 });
  assert.equal(r.status, 402);
  assert.equal(vtpassCalls.length, 0);
  assert.equal(user().balanceKobo, 10000);
});

test('bills: definite failure refunds once', async () => {
  setBalance(100000);
  vtpassPay = () => ({ code: '016', response_description: 'TRANSACTION FAILED' });
  const r = await call('POST', '/bills/pay', { category: 'airtime', serviceID: 'glo', phone: '08011111111', amount: 500 });
  assert.equal(r.body.status, 'failed');
  assert.equal(user().balanceKobo, 100000);
  assert.equal(tx(r.body.id).status, 'failed');
  // Requery after a final state must not refund again.
  await call('POST', '/bills/requery', { id: r.body.id });
  assert.equal(user().balanceKobo, 100000);
});

test('bills: network error stays pending (no refund), requery resolves it', async () => {
  setBalance(100000);
  vtpassPay = () => {
    throw new Error('socket hang up');
  };
  const r = await call('POST', '/bills/pay', { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 500 });
  assert.equal(r.body.status, 'pending');
  assert.equal(user().balanceKobo, 50000);

  vtpassRequery = () => ({ code: '000', content: { transactions: { status: 'failed' } } });
  const q = await call('POST', '/bills/requery', { id: r.body.id });
  assert.equal(q.body.status, 'failed');
  assert.equal(user().balanceKobo, 100000);
});

test('bills: data price comes from VTpass, not the client', async () => {
  setBalance(500000);
  const r = await call('POST', '/bills/pay', {
    category: 'data', serviceID: 'mtn-data', phone: '08011111111', variationCode: 'mtn-1gb', amount: 1,
  });
  assert.equal(r.body.status, 'success');
  assert.equal(user().balanceKobo, 400000);
  assert.equal(vtpassCalls[0].amount, 1000);
});

test('bills: electricity returns the token; bad input rejected', async () => {
  setBalance(500000);
  vtpassPay = () => ({ code: '000', content: { transactions: { status: 'delivered' } }, purchased_code: 'Token : 1234-5678' });
  const r = await call('POST', '/bills/pay', {
    category: 'electricity', serviceID: 'ikeja-electric', phone: '08011111111', billersCode: '1111111111111', meterType: 'prepaid', amount: 2000,
  });
  assert.equal(r.body.token, 'Token : 1234-5678');
  assert.equal(tx(r.body.id).token, 'Token : 1234-5678');

  for (const bad of [
    { category: 'airtime', serviceID: 'not-a-network', phone: '08011111111', amount: 500 },
    { category: 'airtime', serviceID: 'mtn', phone: '123', amount: 500 },
    { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: -500 },
    { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 10.5 },
  ]) {
    assert.equal((await call('POST', '/bills/pay', bad)).status, 400);
  }
  assert.equal(user().balanceKobo, 300000);
});

test('bills: two simultaneous payments cannot overdraw', async () => {
  setBalance(60000);
  const body = { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 500 };
  const results = await Promise.all([call('POST', '/bills/pay', body), call('POST', '/bills/pay', body)]);
  const ok = results.filter((r) => r.status === 200).length;
  assert.equal(ok, 1);
  assert.equal(user().balanceKobo, 10000);
});

test('cannot requery another merchant’s transaction', async () => {
  setBalance(100000);
  const r = await call('POST', '/bills/pay', { category: 'airtime', serviceID: 'mtn', phone: '08011111111', amount: 500 });
  assert.equal((await call('POST', '/bills/requery', { id: r.body.id }, 'mallory')).status, 404);
});
