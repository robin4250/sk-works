const response = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: {'Content-Type':'application/json', 'Cache-Control':'no-store'},
});
// Claims must already be authenticated by the server. Refreshing a token is
// not reauthentication; never trust user_metadata or last_sign_in_at here.
export function recentlyAuthenticated(claims, now) {
  return Array.isArray(claims?.amr) && claims.amr.some(a =>
    ['password','oauth','otp','totp','sso/saml','magiclink'].includes(a?.method) &&
    Number.isInteger(a.timestamp) && a.timestamp <= now && now - a.timestamp <= 600);
}
async function body(req) {
  const reader = req.body?.getReader();
  if (!reader) return null;
  let size = 0; const chunks = [];
  try {
    while (true) {
      const {value,done} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 16384) { await reader.cancel(); return null; }
      chunks.push(value);
    }
    const all = new Uint8Array(size); let offset = 0;
    for (const c of chunks) { all.set(c,offset); offset += c.length; }
    return JSON.parse(new TextDecoder().decode(all));
  } catch { return null; }
  finally { reader.releaseLock(); }
}
export function createHandler({authenticate, configuration, reserve, status, prepareGoogleCredential, now = () => Math.floor(Date.now()/1000)}) {
  return async req => {
    if (!['GET','POST'].includes(req.method)) return response({error:'method_not_allowed'},405);
    try {
      const auth = await authenticate(req);
      if (!auth || auth.user.is_anonymous || auth.claims.sub !== auth.user.id ||
          auth.claims.role !== 'authenticated' || !auth.claims.session_id)
        return response({error:'login_required'},401);
      if (req.method === 'GET') return response({request: await status(auth.user.id,auth.claims.session_id)});
      const input = await body(req);
      if (!input || Object.keys(input).some(k=>!['confirm','google_refresh_token'].includes(k)) || input.confirm !== true ||
          (input.google_refresh_token!==undefined && (typeof input.google_refresh_token!=='string' ||
           !input.google_refresh_token.length || input.google_refresh_token.length>8192)))
        return response({error:'confirmation_required'},400);
      if (!recentlyAuthenticated(auth.claims,now())) return response({error:'reauthentication_required'},403);
      const c = configuration();
      if (!c.enabled || !c.policy || !Number.isInteger(c.days) || c.days < 1 || c.days > 90)
        return response({error:'unavailable'},503);
      const google=auth.user.identities?.some(i=>i.provider==='google');
      if((google || input.google_refresh_token!==undefined) && typeof prepareGoogleCredential!=='function')
       return response({error:'unavailable'},503);
      const credential=typeof prepareGoogleCredential==='function'
       ? await prepareGoogleCredential(auth.user,auth.claims.session_id,input.google_refresh_token) : null;
      const args=[auth.user.id,auth.claims.session_id,c.policy,c.days];
      if(credential) args.push(credential);
      const result = await reserve(...args);
      // Never manufacture completion when only an intake request was saved.
      return response(result,202);
    } catch {
      return response({error:'unavailable'},503);
    }
  };
}
