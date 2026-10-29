// Unhosted candidate boundary. No listener, default activation, grants or keys.
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
class Denied extends Error { constructor(status){super('notice unavailable');this.status=status;} }
const reject=status=>{throw new Denied(status);};
async function body(request){
 if(request.headers.get('content-type')?.split(';')[0]!=='application/json')reject(400);
 const reader=request.body?.getReader();if(!reader)reject(400);
 let size=0;const chunks=[];let timer;
 try{return await Promise.race([(async()=>{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>65536)reject(413);chunks.push(value);}return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));})(),new Promise((_,no)=>{timer=setTimeout(()=>no(new Denied(408)),10000);})]);}
 catch(error){if(error instanceof Denied)throw error;reject(400);}finally{clearTimeout(timer);await reader.cancel().catch(()=>{});}
}
function scope(value,confirm){
 const keys=['ticket_id','local_document_id','company_id','revision','request_id','expected_preview','expected_hash',...(confirm?['financial_confirmed','seal_confirmed']:[])];
 if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).length!==keys.length||Object.keys(value).some(k=>!keys.includes(k)))reject(400);
 if(!['ticket_id','local_document_id','company_id','request_id'].every(k=>typeof value[k]==='string'&&uuid.test(value[k]))||!Number.isSafeInteger(value.revision)||value.revision<1||
  !value.expected_preview||typeof value.expected_preview!=='object'||Array.isArray(value.expected_preview)||!Object.keys(value.expected_preview).length||! /^[a-f0-9]{64}$/.test(value.expected_hash))reject(400);
 if(confirm&&(value.financial_confirmed!==true||value.seal_confirmed!==true))reject(400);
 return value;
}
export function createInvoiceNoticeTransport({enabled=false,authOrigin,apiKey,connect,fetchAuth=fetch}={}){
 if(!enabled)return null;
 const origin=new URL(authOrigin);if(origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash||!(origin.protocol==='https:'||(origin.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(origin.hostname))))throw Error('fixed Auth origin required');
 if(typeof apiKey!=='string'||!apiKey||typeof connect!=='function')throw Error('server configuration required');
 return async request=>{
  let peer,begun=false;
  const response=(status,value)=>new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
  try{
   const route=new URL(request.url).pathname;
   if(request.method!=='POST'||!['/invoice-notice/confirm','/invoice-notice/result'].includes(route))reject(404);
   if(request.headers.has('cookie'))reject(401);
   // Never reread caller headers or accept credentials/issuer in the JSON body.
   const authorization=request.headers.get('authorization');
   if(typeof authorization!=='string'||authorization.length>8192||!/^Bearer [A-Za-z0-9_.-]+$/.test(authorization))reject(401);
   const token=authorization.slice(7),value=scope(await body(request),route.endsWith('/confirm'));
   const authenticated=await fetchAuth(new URL('/auth/v1/user',origin),{method:'GET',redirect:'error',signal:AbortSignal.timeout(5000),headers:{apikey:apiKey,authorization}});
   if(authenticated.status!==200)reject(401);
   const user=await authenticated.json();let claims;
   try{const parts=token.split('.');if(parts.length!==3)reject(401);claims=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8'));}catch{reject(401);}
   if(!uuid.test(user?.id??'')||claims.sub!==user.id||!uuid.test(claims.session_id??'')||claims.role!=='authenticated'||claims.aud!=='authenticated'||claims.iss!==new URL('/auth/v1',origin).href||!Number.isFinite(claims.exp)||claims.exp*1000<=Date.now())reject(401);
   peer=await connect();await peer.query('begin');begun=true;
   await peer.query("set local statement_timeout='10s';set local lock_timeout='5s'");
   await peer.query("select set_config('request.jwt.claims',$1,true),set_config('request.jwt.claim.sub',$2,true)",[JSON.stringify(claims),user.id]);
   // Preserve the existing account/deletion-barrier/user/session lock order.
   // Never replace this sensitive server gate with a decoded-JWT boolean.
   const live=await peer.query('select private.require_reauthentication_session() sid');
   if(live.rows[0]?.sid!==claims.session_id)reject(401);
   const hash=(await peer.query("select encode(sha256(convert_to($1::jsonb::text,'UTF8')),'hex') v",[JSON.stringify(value.expected_preview)])).rows[0].v;
   if(hash!==value.expected_hash)reject(400);
   const args=[value.ticket_id,value.local_document_id,value.company_id,value.revision,JSON.stringify(value.expected_preview),value.request_id];
   const sql=route.endsWith('/confirm')?'select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,$4,$5::jsonb,$6,true,true) v':'select trade_document_consent_private.read_invoice_notice_result_scoped($1,$2,$3,$4,$5::jsonb,$6) v';
   const result=(await peer.query(sql,args)).rows[0].v;
   await peer.query('commit');begun=false;
   return response(200,result);
  }catch(error){
   if(begun&&peer)await peer.query('rollback').catch(()=>{});
   return response(error instanceof Denied?error.status:error?.code==='42501'?403:503,{error:'notice_unavailable'});
  }finally{if(peer)await peer.end().catch(()=>{});}
 };
}
