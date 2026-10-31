import {registerManagerCanonicalSiteOrderJob,processCanonicalSiteOrderReply,processRecoveredSiteOrderReply} from '../../../tool/site_order_canonical_core.mjs';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const commands={
 detail:{keys:['package_id'],sql:'select site_order_package_private.package_decision_detail($1) as result'},
 list:{keys:['before','before_id','limit'],sql:'select site_order_package_private.history_entries($1,$2,$3) as result'},
 site_history:{keys:['site_id','before','before_id','limit'],sql:'select site_order_package_private.site_history_entries($1,$2,$3,$4) as result'},
 outgoing_context:{keys:['site_id','trade_id'],sql:'select site_order_manager_private.outgoing_context($1,$2) as result'},
 observe_prepare:{keys:['site_id','document_id','local_id','trade_id'],sql:'select site_order_manager_private.observe_prepare($1,$2,$3,$4) as result'},
 recipient_targets:{keys:['package_id'],sql:'select site_order_package_private.recipient_targets($1) as result'},
 reconcile_approval:{keys:['package_id','preview_id','request_id'],sql:'select site_order_package_private.reconcile_approval($1,$2,$3) as result'},
 reconcile_refusal:{keys:['package_id','request_id'],sql:'select site_order_package_private.reconcile_refusal($1,$2) as result'},
 refuse:{keys:['package_id','request_id','confirmed'],sql:`with refused as materialized(select site_order_package_private.refuse_order($1,$2,$3) as result) select result||jsonb_build_object('notifications',site_order_package_private.dispatch_refusal_notifications($1)) as result from refused`},
 status:{keys:['package_id'],sql:'select site_order_package_private.package_status($1) as result'},
 archive_payload:{keys:['package_id','kind'],sql:'select site_order_package_private.archive_payload($1,$2) as result'},
 archive:{keys:['package_id','kind'],sql:'select site_order_package_private.archive_original($1,$2) as result',pdf:true},
 preview_approval:{keys:['package_id','trade_id','connection_fingerprint','request_id'],sql:'select site_order_package_private.preview_approval($1,$2,$3,$4) as result'},
 approve:{keys:['preview_id','body_hash','seal_hash','confirmed','request_id'],sql:`with approved as materialized(select site_order_package_private.approve_operation($1,$2,$3,$4,$5) as result) select result||jsonb_build_object('notifications',site_order_package_private.dispatch_notifications((result->>'package_id')::uuid)) as result from approved`},
 send_order:{keys:['job_id','original_receipt_id','request_id'],sql:`with sent as materialized(select site_order_package_private.send_order($1,$2,$3) as result) select result||jsonb_build_object('notifications',site_order_package_private.dispatch_notifications((result->>'package_id')::uuid)) as result from sent`},
 register_original:{keys:['job_id'],worker:true},
 process_reply:{keys:['package_id'],replyWorker:true},
 preview_reply_recovery:{keys:['package_id','request_id'],sql:'select site_order_package_private.preview_reply_recovery($1,$2) as result'},
 confirm_reply_recovery:{keys:['preview_id','body_hash','render_hash','seal_hash','confirmed','request_id'],sql:'select site_order_package_private.confirm_reply_recovery($1,$2,$3,$4,$5,$6) as result'},
 reply_recovery_status:{keys:['package_id','request_id'],sql:'select site_order_package_private.reply_recovery_status($1,$2) as result'},
 reconcile_reply_recovery:{keys:['package_id','preview_id','request_id'],sql:'select site_order_package_private.reconcile_reply_recovery($1,$2,$3) as result'},
 process_recovered_reply:{keys:['package_id','lease_id'],recoveredWorker:true},
};
function response(data,status=200){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});}
async function body(req){
 const reader=req.body?.getReader();if(!reader)throw Error('invalid');
 let size=0;const chunks=[];for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;
 if(size>4096){await reader.cancel();throw Error('invalid');}chunks.push(value);}
 const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
 const b=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 if(!b||typeof b!=='object'||Array.isArray(b))throw Error('invalid');return b;
}
function validate(b){
 const c=commands[b.action];if(!c||Object.keys(b).length!==c.keys.length+1||Object.keys(b).some(k=>k!=='action'&&!c.keys.includes(k)))throw Error('invalid');
 for(const k of c.keys){const v=b[k];
 if(k==='before'){if(v!==null&&(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T[0-9:.+-]+Z?$/.test(v)||!Number.isFinite(Date.parse(v))))throw Error('invalid');}
 else if(k==='before_id'){if(v!==null&&(typeof v!=='string'||!uuid.test(v)))throw Error('invalid');}
 else if(k==='limit'){if(!Number.isInteger(v)||v<1||v>50)throw Error('invalid');}
 else if(k==='kind'){if(!['order','acceptance'].includes(v))throw Error('invalid');}
 else if(k==='confirmed'){if(v!==true)throw Error('invalid');}
 else if(['body_hash','render_hash','seal_hash','connection_fingerprint'].includes(k)){if(typeof v!=='string'||!/^[0-9a-f]{64}$/.test(v))throw Error('invalid');}
 else if(typeof v!=='string'||!uuid.test(v))throw Error('invalid');
 }return c;
}
// Production supplies a fixed verifier, one dedicated connection factory and
// one bundled renderer. None can be selected or supplied by an HTTP request.
export function createSiteOrderHandler({verify,connect,render}){
 return async req=>{
  if(req.method!=='POST')return response({error:'post_required'},405);
  const authorization=req.headers.get('authorization')??'';
  if(authorization.length>16_384||!/^Bearer [^\s]+$/.test(authorization))return response({error:'authentication_required'},401);
  let claims;try{claims=await verify(authorization.slice(7));}catch{return response({error:'authentication_required'},401);}
  let b,c;try{b=await body(req);c=validate(b);}catch{return response({error:'invalid_request'},400);}
  let db,commitStarted=false;
  try{
   db=await connect();
   // The connection is never pooled/reused; close it even after UNKNOWN.
   if(c.replyWorker){const result=await processCanonicalSiteOrderReply(db,b.package_id,render,claims);return response({result});}
   if(c.recoveredWorker){const result=await processRecoveredSiteOrderReply(db,b.package_id,b.lease_id,render,claims);return response({result});}
   if(c.worker){const result=await registerManagerCanonicalSiteOrderJob(db,b.job_id,render,claims);return response({result});}
   await db.query('begin isolation level read committed');
   const role=(await db.query('select session_user as role')).rows[0]?.role;
   if(role!=='postgres')throw Error('internal_connection_required');
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(claims)]);
   const result=(await db.query(c.sql,c.keys.map(k=>b[k]))).rows[0]?.result;
   if(result===undefined||result===null)throw Error('result_required');
   let pdfBytes;
   if(c.pdf){const bytes=result instanceof Uint8Array?result:new Uint8Array(result);
    if(bytes.length<16||bytes.length>20*1024*1024||new TextDecoder().decode(bytes.subarray(0,5))!=='%PDF-')throw Error('original_unavailable');
    pdfBytes=bytes;
   }
   commitStarted=true;await db.query('commit');commitStarted=false;
   if(b.action==='approve'){try{return response({result:await processCanonicalSiteOrderReply(db,result.package_id,render,claims)});}catch(error){return response({result,reply_processing:error?.message?.includes('result_unknown')?'result_unknown':'pending',retry_automatically:false},202);}}
   if(c.pdf){return new Response(pdfBytes,{headers:{'Content-Type':'application/octet-stream','Cache-Control':'no-store','Content-Disposition':'inline; filename="SKO.pdf"'}});
   }
   return response({result});
  }catch(error){
   if(db&&!commitStarted&&!error?.message?.includes('result_unknown'))await db.query('rollback').catch(()=>{});
   const unknown=commitStarted||error?.message?.includes('result_unknown');
   return response({error:unknown?'result_unknown':'operation_rejected',retry_automatically:false},unknown?409:403);
  }finally{if(db)await db.end().catch(()=>{});}
 };
}
