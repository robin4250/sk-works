import {loginRegisteredApple, AppleLoginDenied} from './existing_apple_login.mjs';
const project = 'https://ztktgquxvcxcjxtluspu.supabase.co';
const response = (status, value) => new Response(JSON.stringify(value), {status,
  headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
async function boundedJSON(stream, maximum = 65536) {
  if (!stream) throw new AppleLoginDenied();
  const reader = stream.getReader(); let size = 0; const chunks = [];
  try {
    for (;;) { const {done,value} = await reader.read(); if(done) break;
      size += value.byteLength;if(size > maximum) throw new AppleLoginDenied(); chunks.push(value); }
  } finally { reader.releaseLock(); }
  const all = new Uint8Array(size);let offset=0;
  for(const chunk of chunks){all.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));
}
export function createHandler(env, network = fetch, clock = () => Math.floor(Date.now()/1000)) {
  const audiences = (env.SKO_APPLE_AUDIENCES ?? '').split(',').map(x=>x.trim()).filter(Boolean);
  const publishable = env.SUPABASE_PUBLISHABLE_KEY ?? env.SUPABASE_ANON_KEY;
  const service = env.SUPABASE_SERVICE_ROLE_KEY;
  const configured = env.SKO_APPLE_EXISTING_LOGIN_ENABLED === 'true' &&
    env.SUPABASE_URL === project && !!publishable && typeof service === 'string' &&
    service.split('.').length === 3 && audiences.length > 0 && audiences.length <= 8;
  let cachedKeys = [], expires = 0;
  const request = async (url, init) => {
    const result = await network(url,{...init,redirect:'error',signal:AbortSignal.timeout(10000)});
    if(!result.ok) throw new AppleLoginDenied();
    return result.status===204 ? null : boundedJSON(result.body);
  };
  const rpc = (name, body) => request(project+'/rest/v1/rpc/'+name,{
    method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'content-type':'application/json'},
    body:JSON.stringify(body)});
  const lookup = subject => rpc('resolve_existing_apple_login',{p_apple_subject:subject});
  const ports = {enabled:configured,audiences,now:clock,
    resolveKey:async kid => {
      if(clock()>=expires){
        const keys = await request('https://appleid.apple.com/auth/keys',{method:'GET'});
        if(!Array.isArray(keys?.keys)||keys.keys.length<1||keys.keys.length>10) throw new AppleLoginDenied();
        cachedKeys=keys.keys;expires=clock()+300;
      }
      return cachedKeys.find(k=>k.kid===kid);
    },
    consume:(subject,hash)=>rpc('consume_existing_apple_login',{
      p_apple_subject:subject,p_token_sha256:hash}),
    lookup,
    exchange:(idToken,nonce)=>request(project+'/auth/v1/token?grant_type=id_token',{
      method:'POST',headers:{apikey:publishable,'content-type':'application/json'},
      body:JSON.stringify({provider:'apple',id_token:idToken,nonce})}),
    verifyUser:token=>request(project+'/auth/v1/user',{
      method:'GET',headers:{apikey:publishable,Authorization:'Bearer '+token}}),
    revokeLocal:token=>request(project+'/auth/v1/logout?scope=local',{
      method:'POST',headers:{apikey:publishable,Authorization:'Bearer '+token}}),
  };
  return async req => {
    if(req.method!=='POST')return response(405,{error:'method_not_allowed'});
    if(!configured)return response(503,{error:'apple_existing_login_unavailable'});
    if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json')
      return response(400,{error:'invalid_request'});
    try {
      const body=await boundedJSON(req.body,24576);
      if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).sort().join(',')!=='id_token,nonce')
        throw new AppleLoginDenied();
      const session=await loginRegisteredApple({idToken:body.id_token,rawNonce:body.nonce},ports);
      return response(200,session);
    }catch{return response(403,{error:'apple_existing_login_unavailable',
      message:'登録済みのApple連携を確認できません。Googleなど現在の方法でログインしてください。'});}
  };
}
