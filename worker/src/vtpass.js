import { HttpError } from './util.js';

// Services the app is allowed to sell. The Worker rejects anything else.
export const CATALOG = {
  airtime: ['mtn', 'glo', 'airtel', 'etisalat'],
  data: ['mtn-data', 'glo-data', 'airtel-data', 'etisalat-data'],
  tv: ['dstv', 'gotv', 'startimes'],
  electricity: [
    'ikeja-electric',
    'eko-electric',
    'abuja-electric',
    'kano-electric',
    'portharcourt-electric',
    'jos-electric',
    'ibadan-electric',
    'kaduna-electric',
    'enugu-electric',
    'benin-electric',
    'aba-electric',
    'yola-electric',
  ],
};

export function assertService(category, serviceID) {
  if (!CATALOG[category]?.includes(serviceID)) {
    throw new HttpError(400, 'That service is not available.');
  }
}

async function call(env, method, path, body) {
  const headers = { 'api-key': env.VTPASS_API_KEY, 'content-type': 'application/json' };
  // VTpass: GET requests use the public key, POST requests use the secret key.
  if (method === 'GET') headers['public-key'] = env.VTPASS_PUBLIC_KEY;
  else headers['secret-key'] = env.VTPASS_SECRET_KEY;
  const res = await fetch(env.VTPASS_BASE_URL.replace(/\/$/, '') + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}

export async function variations(env, serviceID) {
  const data = await call(env, 'GET', `/service-variations?serviceID=${encodeURIComponent(serviceID)}`);
  // The API has historically spelled this key "varations".
  const list = data?.content?.variations || data?.content?.varations || [];
  return list.map((v) => ({
    code: v.variation_code,
    name: v.name,
    amount: Math.round(Number(v.variation_amount)),
  }));
}

export async function verifyCustomer(env, { serviceID, billersCode, type }) {
  const data = await call(env, 'POST', '/merchant-verify', { serviceID, billersCode, type });
  const c = data?.content || {};
  if (data?.code !== '000' || c.error) {
    throw new HttpError(400, c.error || 'We could not verify that number. Check it and try again.');
  }
  return { name: c.Customer_Name || c.customer_name || 'Verified customer', address: c.Address || '' };
}

export function pay(env, payload) {
  return call(env, 'POST', '/pay', payload);
}

export function requery(env, requestId) {
  return call(env, 'POST', '/requery', { request_id: requestId });
}

// Response codes that mean the purchase definitely did not happen, so a
// refund is safe. Anything not listed here is treated as "still pending":
// we never refund on an ambiguous answer.
const DEFINITE_FAILURES = new Set([
  '010', '011', '012', '013', '016', '017', '018', '021', '022', '023',
  '024', '027', '028', '030', '034', '035', '040', '085',
]);

/** Maps a VTpass /pay or /requery response to success | pending | failed. */
export function interpret(response) {
  const code = String(response?.code ?? '');
  const txn = response?.content?.transactions || {};
  const token = response?.purchased_code || response?.token || response?.Token || '';
  const message = response?.response_description || '';
  if (code === '000') {
    const status = String(txn.status || '').toLowerCase();
    if (status === 'delivered' || status === 'successful') return { outcome: 'success', token, message };
    if (status === 'failed' || status === 'reversed') return { outcome: 'failed', token: '', message };
    return { outcome: 'pending', token, message };
  }
  if (DEFINITE_FAILURES.has(code)) return { outcome: 'failed', token: '', message };
  return { outcome: 'pending', token: '', message };
}
