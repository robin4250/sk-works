// Runtime-independent broker core. No credentials, logging or account creation.
export class AppleLoginDenied extends Error {
  constructor() { super('apple_existing_login_unavailable'); }
}
const deny = () => { throw new AppleLoginDenied(); };
const encoder = new TextEncoder();
function bytes(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) deny();
  try { return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)); }
  catch { return deny(); }
}
function object(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) deny();
  return value;
}
export async function sha256Hex(value) {
  const raw = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return [...new Uint8Array(raw)].map(v => v.toString(16).padStart(2, '0')).join('');
}
export async function verifyAppleCredential({idToken, rawNonce, audiences, now, resolveKey}) {
  if (typeof idToken !== 'string' || idToken.length > 16384 ||
      typeof rawNonce !== 'string' || !/^[A-Za-z0-9_-]{43,128}$/.test(rawNonce) ||
      !Array.isArray(audiences) || audiences.length < 1 || audiences.length > 8 ||
      audiences.some(a => typeof a !== 'string' || !a || a.length > 255) ||
      !Number.isSafeInteger(now)) deny();
  const parts = idToken.split('.');
  if (parts.length !== 3) deny();
  let header, claims;
  try {
    header = object(JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes(parts[0]))));
    claims = object(JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes(parts[1]))));
  } catch { return deny(); }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(header.kid) || header.jku || header.x5u ||
      claims.iss !== 'https://appleid.apple.com' ||
      typeof claims.aud !== 'string' || !audiences.includes(claims.aud) ||
      typeof claims.sub !== 'string' || !/^[A-Za-z0-9._-]{1,255}$/.test(claims.sub) ||
      !Number.isSafeInteger(claims.iat) || !Number.isSafeInteger(claims.exp) ||
      claims.iat > now + 60 || claims.iat < now - 300 ||
      claims.exp <= now || claims.exp > claims.iat + 86400 || claims.exp <= claims.iat ||
      claims.nonce !== await sha256Hex(rawNonce)) deny();
  let jwk;
  try { jwk = object(await resolveKey(header.kid)); } catch { return deny(); }
  if (jwk.kid !== header.kid || jwk.kty !== 'RSA' || jwk.alg !== 'RS256' ||
      jwk.use !== 'sig' || jwk.d || jwk.p || jwk.q ||
      typeof jwk.n !== 'string' || typeof jwk.e !== 'string') deny();
  try {
    const key = await crypto.subtle.importKey('jwk', jwk,
      {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'}, false, ['verify']);
    if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, bytes(parts[2]),
      encoder.encode(parts[0] + '.' + parts[1]))) deny();
  } catch { return deny(); }
  return Object.freeze({subject:claims.sub, audience:claims.aud,
    tokenHash:await sha256Hex(idToken)});
}
export async function loginRegisteredApple(input, ports) {
  if (ports.enabled !== true) deny();
  const credential = await verifyAppleCredential({...input, now:ports.now(),
    audiences:ports.audiences, resolveKey:ports.resolveKey});
  // Consume a one-use token hash and resolve the exact Apple subject BEFORE
  // GoTrue sees a credential. No email-based lookup or fallback is permitted.
  const before = await ports.consume(credential.subject, credential.tokenHash);
  if (!before || typeof before.user_id !== 'string' ||
      !Array.isArray(before.memberships) || !before.memberships.length ||
      !Array.isArray(before.google_identities)) deny();
  const session = await ports.exchange(input.idToken, input.rawNonce);
  let accepted = false;
  try {
    if (!session || typeof session.access_token !== 'string' || !session.access_token ||
        typeof session.refresh_token !== 'string' || !session.refresh_token ||
        !Number.isSafeInteger(session.expires_in) || session.expires_in <= 0 ||
        session.token_type !== 'bearer' || session.user?.id !== before.user_id) deny();
    const verified = await ports.verifyUser(session.access_token);
    if (!verified || verified.id !== before.user_id || verified.is_anonymous === true ||
        !Array.isArray(verified.identities) || !verified.identities.some(i =>
          i.provider === 'apple' && i.user_id === before.user_id &&
          i.identity_data?.sub === credential.subject)) deny();
    const after = await ports.lookup(credential.subject);
    if (JSON.stringify(after) !== JSON.stringify(before)) deny();
    accepted = true;
    return Object.freeze({access_token:session.access_token,
      refresh_token:session.refresh_token,token_type:'bearer',
      expires_in:session.expires_in,user:verified});
  } finally {
    // This is only the newly issued Apple session. Never revoke the user's
    // existing Google/Face ID sessions or issue a global logout.
    if (!accepted && typeof session?.access_token === 'string') {
      try { await ports.revokeLocal(session.access_token); } catch { /* deny */ }
    }
  }
}
