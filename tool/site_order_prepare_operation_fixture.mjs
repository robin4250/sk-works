import fs from 'node:fs/promises';
import assert from 'node:assert/strict';

export async function verifyPrepareOperations(db,{id,A,B,UA,UB,actor,q,openNativePeer}){
 let checks=0,waits=0;
 const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
 const deny=async(fn,p)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!p.test(error.message))throw Error('expected '+p+' got '+error?.message);checks++;};
 const use=async(connection,uid,sid)=>connection.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[uid,JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);
 const signed=async uid=>{await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);await use(db,uid,sid);return sid;};
 await signed(UA);
 const sql=await fs.readFile('docs/review/site-order-outgoing/prepare-operation.sql.review-only','utf8');
 const originalFunctions=()=>q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p where
  p.pronamespace in('site_order_package_private'::regnamespace,'site_order_manager_private'::regnamespace,
   'trade_document_consent_private'::regnamespace,'site_order_artifact_private'::regnamespace)`);
 const original=await originalFunctions();
 const originals=await q(`select jsonb_build_object(
  'documents',(select jsonb_agg(to_jsonb(d) order by id) from trade_document_consent_private.documents d),
  'revisions',(select jsonb_agg(to_jsonb(r) order by document_id,revision) from trade_document_consent_private.revisions r),
  'consents',(select jsonb_agg(to_jsonb(c) order by document_id,revision,company_id) from trade_document_consent_private.consents c),
  'jobs',(select jsonb_agg(to_jsonb(j) order by id) from site_order_artifact_private.render_jobs j),
  'invoices',(select jsonb_agg(to_jsonb(i) order by id) from public.invoices i),
  'payment_certificates',(select jsonb_agg(to_jsonb(p) order by id) from public.payment_certificates p)) v`);
 await db.exec("do $$begin if not exists(select 1 from pg_roles where rolname='outgoing_operation_untrusted') then create role outgoing_operation_untrusted;end if;end$$");
 for(const [change,pattern] of [
  ['revoke execute on function private.require_standalone_trade_document_access() from authenticated',/outgoing_operation_dependency_changed/],
  ['alter function site_order_manager_private.outgoing_context(uuid,uuid) security invoker',/outgoing_operation_dependency_changed/],
  ['alter default privileges grant execute on functions to outgoing_operation_untrusted',/outgoing_operation_function_acl_changed/],
  ['alter default privileges grant select on tables to outgoing_operation_untrusted',/outgoing_operation_table_acl_changed/],
  ['alter default privileges grant usage on schemas to outgoing_operation_untrusted',/outgoing_operation_namespace_acl_changed/],
 ]){
  await db.exec('begin');
  try{await db.exec(change);await deny(()=>db.exec(sql),pattern);}finally{await db.exec('rollback');}
  check(await q("select to_regnamespace('site_order_outgoing_private') is null v"),true);
  check(await originalFunctions(),original);
 }
 await db.exec(sql);check(await originalFunctions(),original);
 const site=id(9301),trade=id(2100);
 const sample=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-evidence.json','utf8')).body;
 const make=async n=>{
  const context=await q('select site_order_manager_private.outgoing_context($1,$2) v',[site,trade]);
  const x={doc:id(n),local:id(n+1),request:id(n+2),context};
  x.body={...sample,transaction_id:x.doc,issuer_company_id:A,counterparty_company_id:B,issuer:context.issuer,counterparty:context.counterparty};
  return x;
 };
 const params=x=>[site,x.doc,x.local,trade,x.request];
 const prepare=(x,connection=db)=>connection.query('select site_order_outgoing_private.prepare_order($1,$2,$3,$4,$5,$6,$7::jsonb) v',
  [...params(x),x.context.connection_fingerprint,JSON.stringify(x.body)]).then(r=>r.rows[0].v);
 const status=(x,connection=db)=>connection.query('select site_order_outgoing_private.operation_status($1,$2,$3,$4,$5) v',params(x)).then(r=>r.rows[0].v);
 const retire=(x,connection=db,confirmed=true)=>connection.query('select site_order_outgoing_private.retire_prepare($1,$2,$3,$4,$5,$6) v',[...params(x),confirmed]).then(r=>r.rows[0].v);
 const guard=(x,connection=db)=>connection.query('select site_order_outgoing_private.require_unsigned_prepare($1,$2,$3,$4,$5) v',params(x)).then(r=>r.rows[0].v);
 const documentCount=()=>q('select count(*)::int v from trade_document_consent_private.documents');
 const newCounts=x=>q(`select jsonb_build_object('doc',(select count(*) from trade_document_consent_private.documents where id=$1),
  'scope',(select count(*) from site_order_manager_private.document_scopes where document_id=$1),
  'local',(select count(*) from trade_document_consent_private.local_links where company_id=$2 and local_document_id=$3),
  'operation',(select count(*) from site_order_outgoing_private.prepared_operations where company_id=$2 and actor_id=$4 and request_id=$5)) v`,[x.doc,A,x.local,UA,x.request]);
 const unobserved=await make(195000),before=await documentCount();
 check((await status(unobserved)).operation_state,'not_observed');
 check((await status(unobserved)).journal_clearable,false);
 const retired=await retire(unobserved);check(retired.operation_state,'retired');check(retired.order_cancelled,false);
 check(retired.verified_prepared_operation,false);check(retired.journal_clearable,true);
 check(await retire(unobserved),retired);check(await status(unobserved),retired);
 await deny(()=>prepare(unobserved),/outgoing_prepare_retired/);
 check(await documentCount(),before);
 check(await newCounts(unobserved),{doc:0,scope:0,local:0,operation:0});
 await deny(()=>retire({...unobserved,local:id(195009)}),/request_changed/);
 const x=await make(195010),first=await prepare(x),after=await documentCount();
 check(first.operation_state,'prepared_review_required');check(first.can_send,false);
 check(await prepare(x),first);check(await documentCount(),after);
 check((await guard(x)).guard_verified,true);
 check((await status(x)).same_session,true);
 await deny(()=>prepare({...x,body:{...x.body,notes:'changed explicit input'}}),/request_changed/);
 await deny(()=>retire(x,db,false),/identity_required/);
 const kept=await q('select to_jsonb(r) v from trade_document_consent_private.revisions r where document_id=$1 and revision=1',[x.doc]);
 const stop=await retire(x);check(stop.operation_state,'retired');check(stop.verified_prepared_operation,true);
 check(await status(x),stop);await deny(()=>prepare(x),/retired/);await deny(()=>guard(x),/retired/);
 check(await q('select to_jsonb(r) v from trade_document_consent_private.revisions r where document_id=$1 and revision=1',[x.doc]),kept);
 // Late failure after canonical prepare/bind still rolls the entire statement back.
 const rollback=await make(195020);
 await db.exec(`create function pg_temp.reject_operation_insert() returns trigger language plpgsql as $$begin raise exception 'fixture_late_insert_failure';end$$;
  create trigger fixture_operation_insert before insert on site_order_outgoing_private.prepared_operations for each row execute function pg_temp.reject_operation_insert();`);
 await deny(()=>prepare(rollback),/fixture_late_insert_failure/);
 check(await newCounts(rollback),{doc:0,scope:0,local:0,operation:0});
 await db.exec('drop trigger fixture_operation_insert on site_order_outgoing_private.prepared_operations');
 // A new live SID can inspect/retire its actor's unsigned request, never rewrite
 // the saved SID or replay old preparation as a new-session write.
 const oldSid=id(195030),newSid=id(195031);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$2)',[oldSid,UA,newSid]);
 await use(db,UA,oldSid);const sessionCase=await make(195040);await prepare(sessionCase);
 await db.query('delete from auth.sessions where id=$1',[oldSid]);await use(db,UA,newSid);
 check((await status(sessionCase)).same_session,false);
 await deny(()=>prepare(sessionCase),/new_session_review_required/);await deny(()=>guard(sessionCase),/new_session_review_required/);
 const sessionStop=await retire(sessionCase);check(sessionStop.operation_state,'retired');
 check(await q('select session_id v from site_order_outgoing_private.prepared_operations where request_id=$1',[sessionCase.request]),oldSid);
 check(await q('select session_id v from site_order_outgoing_private.prepare_retirements where request_id=$1',[sessionCase.request]),newSid);
 await signed(UA);
 const consent=async(x,connection=db)=>{
  await guard(x,connection);
  const preview=(await connection.query('select site_order_manager_private.preview_own($1,1,$2) v',[x.doc,A])).rows[0].v;
  return (await connection.query("select site_order_manager_private.decide($1,1,$2,$3,$4,'approve',$5,true,$6) v",
   [x.doc,A,preview.epoch,preview.body_hash,preview.own_seal.seal_hash,id(Number.parseInt(x.doc.slice(-8),16)+9)])).rows[0].v;
 };
 const advanced=await make(195050);await prepare(advanced);await db.exec('begin');
 try{await consent(advanced);await db.exec('commit');}finally{await db.exec('rollback');}
 const noCancellation=await retire(advanced);check(noCancellation.operation_state,'advanced');
 check(noCancellation.retired,false);check(noCancellation.order_cancelled,false);check(noCancellation.journal_clearable,false);
 check(await q('select count(*)::int v from site_order_outgoing_private.prepare_retirements where request_id=$1',[advanced.request]),0);
 check(await q('select state v from trade_document_consent_private.revisions where document_id=$1 and revision=1',[advanced.doc]),'approved');
 // OFF blocks preparation but does not weaken the live management gate on stopping.
 const off=await make(195060);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(()=>prepare(off),/master_feature_disabled/);check((await retire(off)).operation_state,'retired');
 await db.query("update company_members set role='worker' where user_id=$1",[UA]);
 await deny(()=>retire({...off,request:id(195069)}),/management_required/);
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await signed(UB);check((await status(x)).operation_state,'not_observed');await signed(UA);
 for(const role of ['authenticated','anon','service_role']){
  await db.exec('set role '+role);await deny(()=>status(x),/permission denied/);await deny(()=>retire(x),/permission denied/);await db.exec('reset role');
 }
 await deny(()=>db.query('update site_order_outgoing_private.prepared_operations set body_sha256=$1 where id=$2',['0'.repeat(64),first.operation_id]),/immutable/);
 await deny(()=>db.exec('truncate site_order_outgoing_private.prepare_retirements'),/immutable/);
 const columns=await q("select jsonb_agg(attname::text order by attnum) v from pg_attribute where attrelid='site_order_outgoing_private.prepared_operations'::regclass and attnum>0 and not attisdropped");
 check(columns.some(name=>['body','payload','seal_snapshot','pdf_bytes','token'].includes(name)),false);

 if(openNativePeer){
  const peer=await openNativePeer();
  const sid=await signed(UA);await use(peer,UA,sid);
  const waitFor=async pid=>{
   let waited=false;
   for(let n=0;n<200&&!waited;n++){
    waited=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[peer.processID,pid]);
    if(!waited)await new Promise(r=>setTimeout(r,5));
   }check(waited,true);waits++;
  };
  try{
   for(const order of ['retire_first','prepare_first']){
    const item=await make(order==='retire_first'?195100:195120);
    await db.exec('begin');
    try{
     if(order==='retire_first')await retire(item);else await prepare(item);
     const pending=(order==='retire_first'?prepare(item,peer):retire(item,peer)).then(value=>({value}),error=>({error}));
     await waitFor(await q('select pg_backend_pid() v'));await db.exec('commit');
     const result=await pending;
     if(order==='retire_first'){
      check(/outgoing_prepare_retired/.test(result.error?.message),true);
      check(await newCounts(item),{doc:0,scope:0,local:0,operation:0});
     }else{
      check(result.value.operation_state,'retired');
      await deny(()=>prepare(item),/retired/);
      check(await q('select state v from trade_document_consent_private.revisions where document_id=$1 and revision=1',[item.doc]),'open');
     }
    }finally{await db.exec('rollback');}
   }
   for(const order of ['retire_first','consent_first']){
    const item=await make(order==='retire_first'?195140:195160);await prepare(item);
    await db.exec('begin');
    try{
     if(order==='retire_first')await retire(item);else await consent(item);
     const peerAction=async()=>{await peer.query('begin');try{const value=order==='retire_first'?await consent(item,peer):await retire(item,peer);await peer.query('commit');return value;}catch(error){await peer.query('rollback');throw error;}};
     const pending=peerAction().then(value=>({value}),error=>({error}));
     await waitFor(await q('select pg_backend_pid() v'));await db.exec('commit');const result=await pending;
     if(order==='retire_first'){
      check(/outgoing_prepare_retired/.test(result.error?.message),true);
      check(await q('select count(*)::int v from trade_document_consent_private.consents where document_id=$1',[item.doc]),0);
     }else{
      check(result.value.operation_state,'advanced');check(result.value.retired,false);check(result.value.order_cancelled,false);
      check(await q('select count(*)::int v from site_order_outgoing_private.prepare_retirements where request_id=$1',[item.request]),0);
     }
    }finally{await db.exec('rollback');}
   }
  }finally{await peer.end();}
  check(waits,4);
 }
 check(await originalFunctions(),original);
 for(const [kind,rows] of Object.entries(originals)){
  if(!rows)continue;
  for(const row of rows){
   const table={documents:'trade_document_consent_private.documents',revisions:'trade_document_consent_private.revisions',consents:'trade_document_consent_private.consents',jobs:'site_order_artifact_private.render_jobs',invoices:'public.invoices',payment_certificates:'public.payment_certificates'}[kind];
   const keys=kind==='revisions'?['document_id','revision']:kind==='consents'?['document_id','revision','company_id']:['id'];
   const value=await q(`select to_jsonb(t) v from ${table} t where ${keys.map((key,n)=>key+'=$'+(n+1)).join(' and ')}`,keys.map(key=>row[key]));
   check(value,row);
  }
 }
 console.log(JSON.stringify({prepare_operation_checks:checks,native_observed_waits:waits,
  two_append_only_id_digest_tables:true,old_functions_and_original_rows_unchanged:true,synthetic_auth:true,production_applied:false}));
}
