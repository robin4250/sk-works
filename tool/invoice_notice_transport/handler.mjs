import {randomUUID} from 'node:crypto';
// Unhosted candidate boundary. No listener, default activation, grants or keys.
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
class Denied extends Error { constructor(status){super('notice unavailable');this.status=status;} }
const reject=status=>{throw new Denied(status);};
const discard=message=>{void message.body?.cancel().catch(()=>{});};
async function boundedJson(message,{limit,milliseconds,status,timeoutStatus=status,signal}){
 if(message.headers.get('content-type')?.split(';')[0]!=='application/json'){discard(message);reject(status);}
 const reader=message.body?.getReader();if(!reader)reject(status);
 const deadline=performance.now()+milliseconds;
 const inTime=()=>{if(performance.now()>=deadline)reject(timeoutStatus);};
 let size=0;const chunks=[];let timer,abort;
 try{return await Promise.race([(async()=>{
  while(true){inTime();const {done,value}=await reader.read();inTime();if(done)break;
   size+=value.byteLength;if(size>limit||chunks.length>=1024)reject(status===400?413:status);chunks.push(value);}
  inTime();const text=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));inTime();
  const value=JSON.parse(text);inTime();return value;
 })(),new Promise((_,no)=>{timer=setTimeout(()=>no(new Denied(timeoutStatus)),milliseconds);}),new Promise((_,no)=>{abort=()=>no(new Denied(504));if(signal?.aborted)abort();else signal?.addEventListener('abort',abort,{once:true});})]);}
 catch(error){if(error instanceof Denied)throw error;reject(status);}
 finally{clearTimeout(timer);if(abort)signal?.removeEventListener('abort',abort);void reader.cancel().catch(()=>{});}
}
function scope(value,confirm){
 const keys=['ticket_id','local_document_id','company_id','revision','request_id','expected_preview','expected_hash',...(confirm?['financial_confirmed','seal_confirmed']:[])];
 if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).length!==keys.length||Object.keys(value).some(k=>!keys.includes(k)))reject(400);
 if(!['ticket_id','local_document_id','company_id','request_id'].every(k=>typeof value[k]==='string'&&uuid.test(value[k]))||!Number.isSafeInteger(value.revision)||value.revision<1||
  !value.expected_preview||typeof value.expected_preview!=='object'||Array.isArray(value.expected_preview)||!Object.keys(value.expected_preview).length||! /^[a-f0-9]{64}$/.test(value.expected_hash))reject(400);
 if(confirm&&(value.financial_confirmed!==true||value.seal_confirmed!==true))reject(400);
 return value;
}
function opening(value){
 const keys=['notification_id','invoice_id','source_revision'];
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==3||Object.keys(value).some(k=>!keys.includes(k))||
  !uuid.test(value.notification_id??'')||!uuid.test(value.invoice_id??'')||typeof value.source_revision!=='string'||value.source_revision.length>80||
  !/(?:Z|[+-][0-9]{2}:[0-9]{2})$/.test(value.source_revision))reject(400);
 return value;
}

export function createInvoiceNoticeTransport({enabled=false,authOrigin,apiKey,connect,fetchAuth=fetch,budgetMs=20000}={}){
 if(!enabled)return null;
 const origin=new URL(authOrigin);if(origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash||!(origin.protocol==='https:'||(origin.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(origin.hostname))))throw Error('fixed Auth origin required');
 if(typeof apiKey!=='string'||!apiKey||typeof connect!=='function'||!Number.isSafeInteger(budgetMs)||budgetMs<1||budgetMs>20000)throw Error('server configuration required');
 return async request=>{
  let peer,begun=false;
  const deadline=performance.now()+budgetMs,controller=new AbortController();
  const expired=()=>controller.signal.aborted||performance.now()>=deadline;
  const ensure=()=>{if(expired()){controller.abort();reject(504);}};
  const timer=setTimeout(()=>controller.abort(),budgetMs);
  const finishes=new WeakMap();
  const finish=value=>{
   if(!finishes.has(value)){const task=Promise.resolve().then(()=>value.end());task.catch(()=>{});finishes.set(value,task);}
   return finishes.get(value);
  };
  // Lazy invocation prevents a queued continuation from starting work after
  // synchronous CPU delay. A late lease is owned and closed, never adopted.
  const run=async(work,onLate)=>{
   ensure();let abort;
   const task=Promise.resolve().then(()=>{ensure();return work();}).then(value=>{
    if(expired()){if(onLate)void Promise.resolve(onLate(value)).catch(()=>{});reject(504);}return value;
   });
   try{const value=await Promise.race([task,new Promise((_,no)=>{abort=()=>no(new Denied(504));controller.signal.addEventListener('abort',abort,{once:true});if(controller.signal.aborted)abort();})]);if(expired()&&onLate)void Promise.resolve(onLate(value)).catch(()=>{});ensure();return value;}
   finally{if(abort)controller.signal.removeEventListener('abort',abort);}
  };
  const response=(status,value)=>new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
  try{
   const route=new URL(request.url).pathname.replace(/^\/functions\/v1(?=\/invoice-notice\/)/,'');
   if(request.method!=='POST'||!['/invoice-notice/open','/invoice-notice/confirm','/invoice-notice/result'].includes(route))reject(404);
   if(request.headers.has('cookie'))reject(401);
   // Never reread caller headers or accept credentials/issuer in the JSON body.
   const authorization=request.headers.get('authorization');
   if(typeof authorization!=='string'||authorization.length>8192||!/^Bearer [A-Za-z0-9_.-]+$/.test(authorization))reject(401);
   const token=authorization.slice(7),raw=await run(()=>boundedJson(request,{limit:65536,milliseconds:10000,status:400,timeoutStatus:408,signal:controller.signal}));
   const value=route.endsWith('/open')?opening(raw):scope(raw,route.endsWith('/confirm'));
   const authUrl=new URL('/auth/v1/user',origin);
   const authenticated=await run(()=>fetchAuth(authUrl,{method:'GET',redirect:'error',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(5000)]),headers:{apikey:apiKey,authorization}}),discard);
   if(authenticated.status!==200||authenticated.redirected!==false||authenticated.url!==authUrl.href){discard(authenticated);reject(401);}
   const user=await run(()=>boundedJson(authenticated,{limit:32768,milliseconds:5000,status:401,signal:controller.signal}));let claims;
   try{const parts=token.split('.');if(parts.length!==3)reject(401);claims=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8'));}catch{reject(401);}
   if(!uuid.test(user?.id??'')||claims.sub!==user.id||!uuid.test(claims.session_id??'')||claims.role!=='authenticated'||claims.aud!=='authenticated'||claims.iss!==new URL('/auth/v1',origin).href||!Number.isFinite(claims.exp)||claims.exp*1000<=Date.now())reject(401);
   ensure();peer=await run(()=>connect(),finish);await run(()=>peer.query('begin'));begun=true;
   await run(()=>peer.query("set local statement_timeout='10s';set local lock_timeout='5s'"));
   await run(()=>peer.query("select set_config('request.jwt.claims',$1,true),set_config('request.jwt.claim.sub',$2,true)",[JSON.stringify(claims),user.id]));
   // Preserve the existing account/deletion-barrier/user/session lock order.
   // Never replace this sensitive server gate with a decoded-JWT boolean.
   const live=await run(()=>peer.query('select private.require_reauthentication_session() sid'));
   if(live.rows[0]?.sid!==claims.session_id)reject(401);
   let result;
   if(route.endsWith('/open')){
    const rollout=await run(()=>peer.query('select enabled from trade_document_consent_private.notice_confirmation_settings where singleton for share'));
    if(rollout.rows[0]?.enabled!==true)reject(503);
    const ticket=(await run(()=>peer.query('select invoice_month_close_candidate.ticket_from_notification($1) v',[value.notification_id]))).rows[0].v;
    if(ticket.invoice_id!==value.invoice_id||ticket.notification_id!==value.notification_id||ticket.status!=='ready')reject(403);
    const rows=await run(()=>peer.query(`select i.id invoice_id,i.company_id,l.local_document_id,d.id document_id,d.current_revision revision,
     r.body,r.body_hash,r.binding,to_jsonb(i.updated_at)#>>'{}' source_revision
     from public.invoices i join trade_document_consent_private.documents d on d.issuer_company_id=i.company_id and d.document_kind='acceptance'
     join trade_document_consent_private.local_links l on l.document_id=d.id and l.company_id=i.company_id
     join trade_document_consent_private.revisions r on r.document_id=d.id and r.revision=d.current_revision
     where i.id=$1 and i.updated_at=$2::timestamptz and r.binding->>'parent_kind'='invoice' and r.binding->>'parent_id'=i.id::text
     order by d.id for share of i,d,l,r`,[ticket.invoice_id,value.source_revision]));
    if(rows.rowCount!==1)reject(403);
    const saved=rows.rows[0];
    if(saved.local_document_id===saved.document_id)reject(403);
    const expected=(await run(()=>peer.query('select trade_document_consent_private.preview_confirmation($1,$2,$3) v',[saved.local_document_id,saved.company_id,saved.revision]))).rows[0].v;
    if(expected.document_id!==saved.document_id||expected.local_document_id!==saved.local_document_id||expected.company_id!==saved.company_id||
       expected.revision!==saved.revision||expected.body_hash!==saved.body_hash||expected.binding?.parent_id!==saved.invoice_id||expected.binding?.parent_kind!=='invoice')reject(403);
    const hash=(await run(()=>peer.query("select encode(sha256(convert_to($1::jsonb::text,'UTF8')),'hex') v",[JSON.stringify(expected)]))).rows[0].v;
    const descriptor={contract_version:1,kind:'invoice',company_id:saved.company_id,actor_id:user.id,parent_id:saved.invoice_id,
     source_revision:saved.source_revision,attachment_version:saved.binding.attachment_version,local_document_id:saved.local_document_id,
     document_id:saved.document_id,document_revision:saved.revision,body_hash:saved.body_hash,preview_hash:hash};
    const workspace={...descriptor,side:'issued',integration_required:true,can_integrated_confirm:true,can_render:false,unavailable_reason:null};
    result={...ticket,source_revision:saved.source_revision,actor_id:user.id,session_id:claims.session_id,
     operation:{ticket_id:ticket.ticket_id,local_document_id:saved.local_document_id,company_id:saved.company_id,revision:saved.revision,
      request_id:randomUUID(),expected_preview:expected,expected_hash:hash},workspace,
     preview:{contract_version:1,expected_command:descriptor,preview_hash:hash,display_preview:{...expected,body:saved.body,body_hash:saved.body_hash}}};
    if(Buffer.byteLength(JSON.stringify(result))>1048576)reject(503);
   }else{
   const hash=(await run(()=>peer.query("select encode(sha256(convert_to($1::jsonb::text,'UTF8')),'hex') v",[JSON.stringify(value.expected_preview)]))).rows[0].v;
   if(hash!==value.expected_hash)reject(400);
   const args=[value.ticket_id,value.local_document_id,value.company_id,value.revision,JSON.stringify(value.expected_preview),value.request_id];
   const sql=route.endsWith('/confirm')?'select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,$4,$5::jsonb,$6,true,true) v':'select trade_document_consent_private.read_invoice_notice_result_scoped($1,$2,$3,$4,$5::jsonb,$6) v';
   result=(await run(()=>peer.query(sql,args))).rows[0].v;
   }
   await run(()=>peer.query('commit'));begun=false;
   await run(()=>finish(peer));
   const reply=response(200,result);ensure();return reply;
  }catch(error){
   if(begun&&peer&&!expired())await run(()=>peer.query('rollback')).catch(()=>{});
   return response(error instanceof Denied?error.status:error?.code==='42501'?403:503,{error:'notice_unavailable'});
  }finally{clearTimeout(timer);controller.abort();if(peer)void finish(peer).catch(()=>{});}
 };
}
