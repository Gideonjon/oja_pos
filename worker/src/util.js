export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}

const ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';

export function randomId(length = 12) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let out = '';
  for (const b of bytes) out += ALPHABET[b % ALPHABET.length];
  return out;
}

/**
 * VTpass request IDs must start with the current Africa/Lagos time as
 * YYYYMMDDHHmm (12 digits), followed by any alphanumeric suffix.
 */
export function lagosRequestId(now = new Date(), suffix = randomId(12)) {
  const d = new Date(now.getTime() + 60 * 60 * 1000); // Lagos is UTC+1, no DST
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${suffix}`
  );
}

export async function hmacSha512Hex(secret, message) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Whole-naira integer within [min, max], or throws a 400. */
export function nairaAmount(value, min, max, label = 'Amount') {
  const n = Number(value);
  if (!Number.isInteger(n)) throw new HttpError(400, `${label} must be a whole number of naira`);
  if (n < min) throw new HttpError(400, `${label} must be at least ₦${min.toLocaleString('en-NG')}`);
  if (n > max) throw new HttpError(400, `${label} cannot be more than ₦${max.toLocaleString('en-NG')}`);
  return n;
}
