const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
// getClaims verifies the JWT signature (JWKS, or Auth server for symmetric keys).
// Never accept merely decoded claims or client-provided identity fields.
export function createProjectVerifier(authClient,projectUrl,now=()=>Date.now()){
 const issuer=new URL('/auth/v1',projectUrl).href.replace(/\/$/,'');
 return async token=>{
  const {data,error}=await authClient.auth.getClaims(token);
  const c=data?.claims;
  if(error||!c||c.iss!==issuer||c.aud!=='authenticated'||c.role!=='authenticated'||c.is_anonymous===true
   ||!uuid.test(c.sub??'')||!uuid.test(c.session_id??'')||!Number.isSafeInteger(c.exp)
   ||c.exp*1000<=now()||!Number.isSafeInteger(c.iat)||c.iat*1000>now()+30_000)
   throw Error('site_order_authentication_required');
  // User-editable metadata is never forwarded into this privileged purpose.
  return Object.fromEntries(['sub','iss','aud','role','session_id','iat','exp','aal','amr','auth_time','is_anonymous']
   .filter(k=>c[k]!==undefined).map(k=>[k,c[k]]));
 };
}
