import { HttpError } from './util.js';

const BASE = 'https://api.paystack.co';

async function call(env, path, init = {}) {
  const res = await fetch(BASE + path, {
    ...init,
    headers: {
      authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
      'content-type': 'application/json',
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.status !== true) {
    throw new HttpError(502, body.message || 'Paystack is not responding. Try again.');
  }
  return body.data;
}

export function initializeTransaction(env, { email, kobo, reference, metadata }) {
  return call(env, '/transaction/initialize', {
    method: 'POST',
    body: JSON.stringify({
      email,
      amount: kobo,
      currency: 'NGN',
      reference,
      metadata,
    }),
  });
}

export function verifyTransaction(env, reference) {
  return call(env, `/transaction/verify/${encodeURIComponent(reference)}`);
}
