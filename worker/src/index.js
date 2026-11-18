// Oja POS API — Cloudflare Worker.
// Holds every secret (Paystack, VTpass, Firebase service account) so the
// Flutter app never does. Every money movement is decided here.

import { verifyFirebaseUser } from './auth.js';
import * as db from './firestore.js';
import * as paystack from './paystack.js';
import * as vtpass from './vtpass.js';
import {
  HttpError,
  hmacSha512Hex,
  json,
  lagosRequestId,
  nairaAmount,
  randomId,
  timingSafeEqual,
} from './util.js';

const PHONE = /^0[789][01]\d{8}$/;

function corsHeaders(request, env) {
  const allowed = (env.ALLOWED_ORIGINS || '*').split(',').map((s) => s.trim());
  const origin = request.headers.get('origin') || '';
  const allow = allowed.includes('*') ? '*' : allowed.includes(origin) ? origin : allowed[0];
  return {
    'access-control-allow-origin': allow,
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}

async function readBody(request) {
  try {
    const body = await request.json();
    if (body && typeof body === 'object') return body;
  } catch {
    // fall through
  }
  throw new HttpError(400, 'Invalid request');
}

// ---------- rates ----------

let rateCache = null;

async function getRates() {
  if (rateCache && Date.now() - rateCache.at < 60_000) return rateCache.value;
  try {
    const res = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=ngn,usd',
      { headers: { accept: 'application/json' } },
    );
    const data = await res.json();
    const btcNgn = Number(data?.bitcoin?.ngn);
    if (!res.ok || !(btcNgn > 0)) throw new Error('bad rate');
    rateCache = {
      at: Date.now(),
      value: { btcNgn, btcUsd: Number(data.bitcoin.usd) || null, updatedAt: new Date().toISOString() },
    };
    return rateCache.value;
  } catch {
    if (rateCache) return rateCache.value; // serve the last good rate
    throw new HttpError(503, 'Could not fetch the Bitcoin rate. Try again in a moment.');
  }
}

// ---------- Paystack ----------

async function paystackInitialize(env, user, body) {
  const naira = nairaAmount(body.amount, 100, 5_000_000);
  const purpose = body.purpose === 'topup' ? 'topup' : 'sale';
  const note = String(body.note || '').slice(0, 80);
  const reference = `oja_${Date.now()}_${randomId(10)}`;
  const kobo = naira * 100;
  // Our own record of what this reference is for. We trust this, not the
  // metadata that comes back from the payment page.
  await db.setDoc(env, `paystack_refs/${reference}`, {
    uid: user.uid,
    kobo,
    purpose,
    note,
    status: 'pending',
    createdAt: new Date(),
  });
  const data = await paystack.initializeTransaction(env, {
    email: user.email,
    kobo,
    reference,
    metadata: { uid: user.uid, purpose },
  });
  return { reference, authorizationUrl: data.authorization_url, accessCode: data.access_code };
}

/** Checks a reference with Paystack and credits the merchant exactly once. */
async function settlePaystack(env, reference, expectedUid) {
  const ref = await db.getDoc(env, `paystack_refs/${reference}`);
  if (!ref || (expectedUid && ref.data.uid !== expectedUid)) {
    throw new HttpError(404, 'Payment not found');
  }
  if (ref.data.status === 'success') return { status: 'success', amountKobo: ref.data.kobo };

  const data = await paystack.verifyTransaction(env, reference);
  if (data.status === 'success') {
    if (data.amount !== ref.data.kobo || data.currency !== 'NGN') {
      await db.mergeDoc(env, `paystack_refs/${reference}`, { status: 'mismatch' });
      throw new HttpError(409, 'Payment amount did not match. Contact support.');
    }
    await db.credit(env, {
      uid: ref.data.uid,
      txId: reference,
      kobo: ref.data.kobo,
      tx: {
        type: ref.data.purpose === 'topup' ? 'topup' : 'sale',
        method: 'paystack',
        status: 'success',
        amountKobo: ref.data.kobo,
        note: ref.data.note || (ref.data.purpose === 'topup' ? 'Float top-up' : 'Card / transfer sale'),
        channel: data.channel || '',
        createdAt: new Date(),
      },
    });
    await db.mergeDoc(env, `paystack_refs/${reference}`, { status: 'success' });
    return { status: 'success', amountKobo: ref.data.kobo };
  }
  if (data.status === 'failed' || data.status === 'reversed') return { status: 'failed' };
  return { status: 'pending' }; // abandoned / ongoing / pending: customer may still pay
}

async function paystackWebhook(request, env) {
  const raw = await request.text();
  const signature = request.headers.get('x-paystack-signature') || '';
  const expected = await hmacSha512Hex(env.PAYSTACK_SECRET_KEY, raw);
  if (!timingSafeEqual(signature, expected)) throw new HttpError(401, 'Bad signature');
  const event = JSON.parse(raw);
  const reference = event?.data?.reference;
  if (event?.event === 'charge.success' && typeof reference === 'string' && reference.startsWith('oja_')) {
    // We still re-verify with Paystack before crediting.
    // An unknown reference is ignored; any other error returns 500 so that
    // Paystack retries the webhook later.
    await settlePaystack(env, reference, null).catch((e) => {
      if (!(e instanceof HttpError && e.status === 404)) throw e;
    });
  }
  return { received: true };
}

// ---------- Bills (VTpass) ----------

const LABELS = { airtime: 'Airtime', data: 'Data', tv: 'TV subscription', electricity: 'Electricity' };

async function billsPay(env, user, body) {
  const category = String(body.category || '');
  const serviceID = String(body.serviceID || '');
  vtpass.assertService(category, serviceID);

  const phone = String(body.phone || '').replace(/\s+/g, '');
  if (!PHONE.test(phone)) throw new HttpError(400, 'Enter a valid 11-digit Nigerian phone number.');

  const payload = { serviceID, phone };
  let naira;
  let planName = '';

  if (category === 'airtime') {
    naira = nairaAmount(body.amount, 50, 50_000);
    payload.amount = naira;
  } else if (category === 'electricity') {
    naira = nairaAmount(body.amount, 500, 500_000);
    const meterType = body.meterType === 'postpaid' ? 'postpaid' : 'prepaid';
    const meter = String(body.billersCode || '').trim();
    if (!/^\d{6,20}$/.test(meter)) throw new HttpError(400, 'Enter a valid meter number.');
    Object.assign(payload, { amount: naira, billersCode: meter, variation_code: meterType });
  } else {
    // Data and TV: the price comes from VTpass, never from the client.
    const code = String(body.variationCode || '');
    const plan = (await vtpass.variations(env, serviceID)).find((v) => v.code === code);
    if (!plan || !(plan.amount > 0)) throw new HttpError(400, 'That plan is no longer available.');
    naira = plan.amount;
    payload.variation_code = code;
    payload.amount = naira;
    if (category === 'data') {
      payload.billersCode = phone;
    } else {
      const card = String(body.billersCode || '').trim();
      if (!/^\d{6,20}$/.test(card)) throw new HttpError(400, 'Enter a valid smartcard / IUC number.');
      payload.billersCode = card;
      payload.subscription_type = 'change';
    }
    planName = plan.name;
  }

  const kobo = naira * 100;
  const requestId = lagosRequestId();
  payload.request_id = requestId;

  // 1. Take the money and create the pending transaction atomically.
  await db.debit(env, {
    uid: user.uid,
    txId: requestId,
    kobo,
    tx: {
      type: 'bill',
      method: 'float',
      status: 'pending',
      amountKobo: kobo,
      note: `${LABELS[category]} · ${serviceID.replace(/-/g, ' ')}`,
      category,
      serviceID,
      recipient: payload.billersCode || phone,
      planName,
      createdAt: new Date(),
    },
  });

  // 2. Ask VTpass to deliver. A network error here is NOT a failure: the
  //    purchase may have gone through, so it stays pending until requeried.
  let result;
  try {
    result = vtpass.interpret(await vtpass.pay(env, payload));
  } catch {
    result = { outcome: 'pending', token: '', message: '' };
  }
  return finishBill(env, user.uid, requestId, kobo, result);
}

async function finishBill(env, uid, requestId, kobo, result) {
  if (result.outcome === 'success') {
    await db.settleTx(env, { uid, txId: requestId, status: 'success', patch: { token: result.token || '' } });
  } else if (result.outcome === 'failed') {
    await db.settleTx(env, {
      uid,
      txId: requestId,
      status: 'failed',
      patch: { failureReason: result.message || 'Provider declined' },
      refundKobo: kobo,
    });
  }
  return {
    id: requestId,
    status: result.outcome,
    token: result.token || '',
    message:
      result.outcome === 'success'
        ? 'Delivered'
        : result.outcome === 'failed'
          ? 'This purchase failed and your float has been refunded.'
          : 'Processing. We will update this transaction shortly.',
  };
}

async function billsRequery(env, user, body) {
  const id = String(body.id || '');
  if (!/^\d{12}[a-z0-9]+$/.test(id)) throw new HttpError(400, 'Invalid transaction');
  const tx = await db.getTx(env, user.uid, id);
  if (!tx || tx.data.type !== 'bill') throw new HttpError(404, 'Transaction not found');
  if (tx.data.status !== 'pending') {
    return { id, status: tx.data.status, token: tx.data.token || '', message: '' };
  }
  const result = vtpass.interpret(await vtpass.requery(env, id));
  return finishBill(env, user.uid, id, tx.data.amountKobo, result);
}

// ---------- router ----------

export function createApp({ verifyUser = verifyFirebaseUser } = {}) {
  async function route(request, env) {
    const url = new URL(request.url);
    const key = `${request.method} ${url.pathname.replace(/\/+$/, '') || '/'}`;

    // Public routes
    if (key === 'GET /' || key === 'GET /health') return { ok: true, service: 'oja-pos-api' };
    if (key === 'GET /rates') return getRates();
    if (key === 'POST /paystack/webhook') return paystackWebhook(request, env);

    // Everything below needs a signed-in merchant.
    const user = await verifyUser(request, env);

    switch (key) {
      case 'POST /paystack/initialize':
        return paystackInitialize(env, user, await readBody(request));
      case 'POST /paystack/verify': {
        const { reference } = await readBody(request);
        if (typeof reference !== 'string' || !reference.startsWith('oja_')) {
          throw new HttpError(400, 'Invalid reference');
        }
        return settlePaystack(env, reference, user.uid);
      }
      case 'GET /bills/variations': {
        const serviceID = url.searchParams.get('serviceID') || '';
        const category = serviceID.endsWith('-data') ? 'data' : 'tv';
        vtpass.assertService(category, serviceID);
        return { variations: await vtpass.variations(env, serviceID) };
      }
      case 'POST /bills/verify-customer': {
        const body = await readBody(request);
        const category = String(body.category || '');
        vtpass.assertService(category, String(body.serviceID || ''));
        if (category !== 'tv' && category !== 'electricity') throw new HttpError(400, 'Nothing to verify');
        return vtpass.verifyCustomer(env, {
          serviceID: body.serviceID,
          billersCode: String(body.billersCode || '').trim(),
          type: category === 'electricity' ? (body.meterType === 'postpaid' ? 'postpaid' : 'prepaid') : undefined,
        });
      }
      case 'POST /bills/pay':
        return billsPay(env, user, await readBody(request));
      case 'POST /bills/requery':
        return billsRequery(env, user, await readBody(request));
      default:
        throw new HttpError(404, 'Not found');
    }
  }

  return {
    async fetch(request, env) {
      const cors = corsHeaders(request, env);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
      try {
        return json(await route(request, env), 200, cors);
      } catch (e) {
        if (e instanceof HttpError) return json({ error: e.message }, e.status, cors);
        console.error('Unhandled error', e?.stack || e);
        return json({ error: 'Something went wrong. Please try again.' }, 500, cors);
      }
    },
  };
}

export default createApp();
