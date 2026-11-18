import { createRemoteJWKSet, jwtVerify } from 'jose';
import { HttpError } from './util.js';

// Public keys Google uses to sign Firebase Auth ID tokens.
const JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

/** Verifies the Firebase ID token on the request and returns { uid, email }. */
export async function verifyFirebaseUser(request, env) {
  const header = request.headers.get('authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, 'Please sign in to continue.');
  try {
    const { payload } = await jwtVerify(match[1], JWKS, {
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
      algorithms: ['RS256'],
    });
    if (!payload.sub) throw new Error('no subject');
    return { uid: payload.sub, email: payload.email || `${payload.sub}@merchant.ojapos.app` };
  } catch {
    throw new HttpError(401, 'Your session has expired. Please sign in again.');
  }
}
