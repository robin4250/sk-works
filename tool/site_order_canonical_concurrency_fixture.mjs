import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createCanonicalSiteOrderRenderer,registerCanonicalSiteOrderJob} from './site_order_canonical_renderer.mjs';
export async function verifyCanonicalConcurrentOriginal(db,c){
 const {id,A,B,UA,actor,q,prepare,preview,decide,openNativePeer}=c;
 if(!openNativePeer)throw Error('Independent native PostgreSQL connections required');
 await actor(UA);const sid=await q('select id v from auth.sessions where user_id=$1',[UA]);
 const claims=JSON.stringify({sub:UA,role:'authenticated',session_id:sid});
 await db.query("select set_config('test.jwt',$1,false)",[claims]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const names=await q('select jsonb_object_agg(id,name) v from companies');
 const sample=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-evidence.json','utf8'));
 const doc=id(11000),body={...sample.body,issuer_company_id:A,counterparty_company_id:B,
  issuer:{...sample.body.issuer,name:names[A]},counterparty:{...sample.body.counterparty,name:names[B]}};
 await prepare(doc,0,body);await decide(doc,1,A,await preview(doc,1,A));
 const job=await q('select site_order_artifact_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,id(9301),doc,id(11001),id(2100)]);
 const evidence=await q('select evidence v from site_order_artifact_private.render_jobs where id=$1',[job.job_id]);
 const render=await createCanonicalSiteOrderRenderer({dartExecutable:process.env.SKO_CANONICAL_DART,repositoryRoot:process.cwd()});
 const bytes=await render(evidence);
 const firstDb=await openNativePeer(),secondDb=await openNativePeer();
 let release,firstStarted,first,second;const started=new Promise(r=>{firstStarted=r;});const resume=new Promise(r=>{release=r;});
 let firstCalls=0,secondCalls=0,firstIsolation,secondIsolation;
 try{
  for(const peer of [firstDb,secondDb])await peer.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[UA,claims]);
  await secondDb.query("set default_transaction_isolation='repeatable read'");
  const auditedSecond={query:async(sql,args)=>{const result=await secondDb.query(sql,args);if(sql==='begin isolation level read committed')secondIsolation=(await secondDb.query('show transaction_isolation')).rows[0].transaction_isolation;return result;}};
  first=registerCanonicalSiteOrderJob(firstDb,job.job_id,async value=>{
   firstIsolation=(await firstDb.query('show transaction_isolation')).rows[0].transaction_isolation;
   assert.deepEqual(value,evidence);firstCalls++;firstStarted();await resume;return bytes;
  });first.catch(()=>{});await started;
  second=registerCanonicalSiteOrderJob(auditedSecond,job.job_id,async value=>{
   assert.deepEqual(value,evidence);secondCalls++;return bytes;
  });second.catch(()=>{});
  let blocked=false;
  for(let i=0;i<100&&!blocked;i++){
   await db.query('select pg_stat_clear_snapshot()');
   blocked=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[secondDb.processID,firstDb.processID]);
   if(!blocked)await new Promise(r=>setTimeout(r,10));
  }
  assert.equal(blocked,true,'Second request must actually wait for the first job lock');
  release();const [a,b]=await Promise.all([first,second]);
  assert.deepEqual(a,b,'Concurrent request must return the same immutable receipt');
  assert.equal(firstCalls,1);assert.equal(firstIsolation,'read committed');assert.equal(secondIsolation,'read committed');
  assert.equal(secondCalls,0,'Second request rerendered after waiting: stale joined-original snapshot');
  assert.equal(await q('select count(*)::int v from site_order_artifact_private.pdf_records where job_id=$1',[job.job_id]),1);
  console.log('PASS native concurrent original: observed job-lock wait; first render once; second render zero; same original receipt; default RR explicitly overridden');
 }finally{
  release();await Promise.allSettled([first,second].filter(Boolean));
  await firstDb.end();await secondDb.end();
 }
}
