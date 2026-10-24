// Native-only two-connection races over the existing financial approval functions.
// All actors/rows come from the disposable loopback fixture, never a real JWT.
import assert from 'node:assert/strict';

export async function verifyInvoiceConfirmationRaces(db,c){
 const {id,A,UA,actor,q,check,deny,render,prepare,preview,state,openNativePeer}=c;
 const confirmSql='select trade_document_consent_private.confirm_local_document($1,$2,1,$3::jsonb,$4,true,true) v';
 const confirm=(peer,x,p,rid)=>peer.query(confirmSql,[x.local,A,JSON.stringify(p),rid]).then(r=>r.rows[0].v);
 const begin=peer=>peer.query('begin');
 const commit=peer=>peer.query('commit');
 const tracked=promise=>{const task={done:false};task.result=promise.then(value=>({ok:true,value}),error=>({ok:false,error})).then(outcome=>{task.done=true;return outcome;});return task;};
 const lockWait=async(peer,holder,task)=>{
  const until=Date.now()+5000;
  while(Date.now()<until){
   if(task.done){const outcome=await task.result;throw Error('race did not wait for transaction lock: '+(outcome.ok?'completed':outcome.error.message));}
   const row=(await db.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[peer.processID])).rows[0];
   if(row?.wait_event_type==='Lock'&&row.blockers.includes(holder.processID)){check(task.done,false);check(row.blockers.includes(holder.processID),true);return;}
   await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw Error('native transaction lock was not observed within five seconds');
 };
 const peers=async run=>{
  let one,two;
  try{
   one=await openNativePeer();two=await openNativePeer();
   for(const peer of [one,two]){
    await peer.query("set statement_timeout='15s';set lock_timeout='10s'");
    await peer.query("select set_config('test.uid',$1,false),set_config('test.blocked','false',false),set_config('test.invoice_manage','true',false),set_config('test.invoice_view','true',false)",[UA]);
    check((await peer.query('select current_database() name')).rows[0].name,'sko_document_consent_fixture');
   }
   await run(one,two);
  }finally{
   // Release the holder before draining the blocked command, even on assertion failure.
   await Promise.allSettled([one,two].filter(Boolean).map(peer=>peer.query('rollback')));
   await Promise.allSettled([one,two].filter(Boolean).map(peer=>peer.end()));
  }
 };

 // Same request arrives while its first transaction is still uncommitted.
 // The second connection must wait, then return the durable identical receipt.
 const duplicate=await prepare(100),dp=await preview(duplicate),before=await state(duplicate),rid=id(9100);
 await peers(async(one,two)=>{
  await begin(one);const first=await confirm(one,duplicate,dp,rid);
  const repeat=tracked(confirm(two,duplicate,dp,rid));await lockWait(two,one,repeat);
  await commit(one);const outcome=await repeat.result;assert.equal(outcome.ok,true,outcome.error?.message);check(outcome.value,first);
  const after=await state(duplicate);
  check(after.audit,1);check(after.consents,1);check(after.receipts,1);check(after.events,1);
  check(after.primitive_receipts,before.primitive_receipts+1);check(after.approvals[0].status,'approved');check(after.parent.invoice_seal_frozen,true);
  check(after.revision.binding,before.revision.binding);
  // This is a known-COMMIT reconnect replay, not proof of an unknown/lost COMMIT ACK.
  await one.end();const reconnected=await openNativePeer();
  try{await reconnected.query("set statement_timeout='15s';set lock_timeout='10s'");await reconnected.query("select set_config('test.uid',$1,false)",[UA]);check(await confirm(reconnected,duplicate,dp,rid),first);}finally{await reconnected.end();}
  check(await state(duplicate),after);
 });

 // A competing material edit commits before the confirmation obtains its locks.
 // Its old preview must fail and leave every seal/financial evidence row untouched.
 const changed=await prepare(101),cp=await preview(changed);
 await peers(async(one,two)=>{
  await begin(one);await one.query('update public.invoices set grand_total=grand_total+1 where id=$1',[changed.parent]);
  const pending=tracked(confirm(two,changed,cp,id(9101)));await lockWait(two,one,pending);
  await commit(one);const edited=await state(changed),outcome=await pending.result;
  check(outcome.ok,false);check(outcome.error.code,'40001');check(/changed/.test(outcome.error.message),true);
  check(await state(changed),edited);check(edited.audit,0);check(edited.consents,0);check(edited.receipts,0);check(edited.events,0);
 });

 // The opposite order: approval commits, then the waiting editor invalidates the
 // current approval normally. The original issued evidence survives only in archive.
 const editedAfter=await prepare(102),ep=await preview(editedAfter);
 await peers(async(one,two)=>{
  await begin(one);await confirm(one,editedAfter,ep,id(9102));
  const editing=tracked(two.query('update public.invoices set grand_total=grand_total+1 where id=$1',[editedAfter.parent]));
  await lockWait(two,one,editing);await commit(one);const outcome=await editing.result;assert.equal(outcome.ok,true,outcome.error?.message);
  await actor(UA);await deny(()=>render(editedAfter.doc,1,A),/changed/);
  const archived=await render(editedAfter.doc,1,A,true);check(archived.document_id,editedAfter.doc);
  const after=await state(editedAfter);check(after.consents,1);check(after.receipts,1);check(after.events,1);check(after.approvals[0].status,'pending');
  check(await q('select count(*)::int v from trade_document_consent_private.financial_receipts where request_id=$1',[id(9102)]),1);
 });
 console.log('PASS native invoice races: observed two-connection locks; duplicate request once; known-COMMIT reconnect replay; material edit before/after confirmation; immutable archived receipt. No JWT/session/unknown-COMMIT rollout proof.');
}
