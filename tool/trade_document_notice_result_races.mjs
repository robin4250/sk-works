// Native-only, synthetic actors. Observes transaction locks, never hosted Auth.
import assert from 'node:assert/strict';

export async function verifyNoticeResultRaces(db,c){
 const {A,UA,id,check,prepare,preview,issue,state,openNativePeer}=c;
 const x=await prepare(25),expected=await preview(x),ticket=await issue(x),rid=id(29025);
 const args=[ticket,x.local,A,JSON.stringify(expected),rid];
 const confirm=peer=>peer.query('select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,1,$4::jsonb,$5,true,true) v',args).then(r=>r.rows[0].v);
 const read=peer=>peer.query('select trade_document_consent_private.read_invoice_notice_result($1,$2,$3,1,$4::jsonb,$5) v',args).then(r=>r.rows[0].v);
 let one,two,reconnected,waiting;
 try{
  one=await openNativePeer();two=await openNativePeer();
  for(const peer of [one,two]){
   await peer.query("set statement_timeout='15s';set lock_timeout='10s'");
   await peer.query("select set_config('test.uid',$1,false),set_config('test.notice_sid',$2,false)",[UA,id(9001)]);
  }
  await one.query('begin');const result=await confirm(one);
  // An uncommitted success must not be exposed as a durable result.
  check(await read(two),{found:false});
  let finished=false;
  waiting=confirm(two).then(value=>({ok:true,value}),error=>({ok:false,error})).then(value=>{finished=true;return value;});
  let blocked=false;
  for(let attempt=0;attempt<200;attempt++){
   if(finished)throw Error('duplicate notice confirmation did not wait for its company lock');
   const row=(await db.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[two.processID])).rows[0];
   if(row?.wait_event_type==='Lock'&&row.blockers.includes(one.processID)){blocked=true;break;}
   await new Promise(resolve=>setTimeout(resolve,25));
  }
  check(blocked,true);await one.query('commit');
  const duplicate=await waiting;check(duplicate.ok,false);check(duplicate.error.code,'42501');
  assert.match(duplicate.error.message,/notice_unavailable/);
  check(await read(two),{found:true,status:'recorded',result});
  reconnected=await openNativePeer();
  await reconnected.query("select set_config('test.uid',$1,false),set_config('test.notice_sid',$2,false)",[UA,id(9001)]);
  check(await read(reconnected),{found:true,status:'recorded',result});
  const after=await state(x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);
  check((await db.query('select count(*)::int v from trade_document_consent_private.notice_confirmation_results where ticket_id=$1',[ticket])).rows[0].v,1);
  console.log('PASS native notice result: uncommitted result absent, observed duplicate lock, consumed-ticket denial, one durable result after COMMIT/reconnect; no unknown-COMMIT ACK or live Auth proof');
 }finally{
  if(one)await one.query('rollback').catch(()=>{});
  if(waiting)await waiting;
  await Promise.allSettled([one,two,reconnected].filter(Boolean).map(peer=>peer.end()));
 }
}
