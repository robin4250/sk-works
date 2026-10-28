// Native PostgreSQL transport failure proof, with synthetic actor/session scope.
// The application receives a failed COMMIT future, not a successful ACK that the
// test later discards. No public API, hosted endpoint or real Auth claim here.
import assert from 'node:assert/strict';
import {createNoticeCommitAckProxy} from './trade_document_notice_commit_ack_proxy.mjs';

export async function verifyNoticeCommitAckLoss(db,c){
 const {A,UA,id,check,prepare,preview,issue,state,openNativePeer}=c;
 const pg=(await import(process.argv[2])).default;
 const target=process.env.SKO_CONSENT_FIXTURE_URL;
 const setActor=peer=>peer.query("select set_config('test.uid',$1,false),set_config('test.notice_sid',$2,false)",[UA,id(9001)]);
 const makeArgs=async num=>{
  const x=await prepare(num),expected=await preview(x),ticket=await issue(x);
  return {x,args:[ticket,x.local,A,JSON.stringify(expected),id(29000+num)]};
 };
 const confirm=(peer,args)=>peer.query('select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,1,$4::jsonb,$5,true,true) v',args).then(r=>r.rows[0].v);
 const read=(peer,args)=>peer.query('select trade_document_consent_private.read_invoice_notice_result($1,$2,$3,1,$4::jsonb,$5) v',args).then(r=>r.rows[0].v);
 const results=args=>db.query('select count(*)::int v from trade_document_consent_private.notice_confirmation_results where ticket_id=$1',[args[0]]).then(r=>r.rows[0].v);
 let proxy,client,recovered;
 try{
  const committed=await makeArgs(26);
  proxy=await createNoticeCommitAckProxy(target,{reviewOnly:true});
  client=new pg.Client({connectionString:proxy.connectionString,connectionTimeoutMillis:5000,ssl:false});
  client.on('error',()=>{});await client.connect();await setActor(client);
  await client.query("set synchronous_commit=on;set statement_timeout='10s';set lock_timeout='5s'");
  await client.query('begin');const provisional=await confirm(client,committed.args);
  check(await results(committed.args),0);
  proxy.armCommitDrop();
  // The server has executed COMMIT, but its CommandComplete/ReadyForQuery never
  // reach this pg client. Do not infer rollback from this transport exception.
  let acknowledged=false,commitFailed=false;
  try{await client.query('commit');acknowledged=true;}catch{commitFailed=true;}
  await proxy.waitForDrop();check(proxy.dropped,true);check(acknowledged,false);check(commitFailed,true);
  recovered=await openNativePeer();await setActor(recovered);
  check(await read(recovered,committed.args),{found:true,status:'recorded',result:provisional});
  await recovered.query("select set_config('test.notice_sid',$1,false)",[id(9002)]);
  await c.deny(()=>read(recovered,committed.args),/notice_result_unavailable/);
  await recovered.query("select set_config('test.notice_sid','',false)");
  await c.deny(()=>read(recovered,committed.args),/notice_result_unavailable/);
  await setActor(recovered);
  check(await read(recovered,committed.args),{found:true,status:'recorded',result:provisional});
  check(await results(committed.args),1);
  const after=await state(committed.x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);
  check(after.approvals[0].status,'approved');check(after.parent.invoice_seal_frozen,true);
  check((await db.query('select consumed_at is not null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[committed.args[0]])).rows[0].v,true);
  await recovered.end();recovered=null;await proxy.close();proxy=null;
  await client.end().catch(()=>{});client=null;

  // Opposite transport outcome: the connection dies before COMMIT. The same
  // explicit historical read must return missing, never guessed success or retry.
  const rolledBack=await makeArgs(27),before=await state(rolledBack.x);
  proxy=await createNoticeCommitAckProxy(target,{reviewOnly:true});
  client=new pg.Client({connectionString:proxy.connectionString,connectionTimeoutMillis:5000,ssl:false});
  client.on('error',()=>{});await client.connect();await setActor(client);
  const pid=client.processID;
  await client.query('begin');await confirm(client,rolledBack.args);
  await proxy.close();proxy=null;
  let ended=false;
  for(let attempt=0;attempt<200;attempt++){
   const row=(await db.query('select count(*)::int n from pg_stat_activity where pid=$1',[pid])).rows[0];
   if(row.n===0){ended=true;break;}await new Promise(resolve=>setTimeout(resolve,25));
  }
  check(ended,true);recovered=await openNativePeer();await setActor(recovered);
  check(await read(recovered,rolledBack.args),{found:false});check(await results(rolledBack.args),0);
  check(await state(rolledBack.x),before);
  check((await db.query('select consumed_at is not null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[rolledBack.args[0]])).rows[0].v,false);
  check((await db.query('select count(*)::int v from invoice_month_close_candidate.approval_permits')).rows[0].v,0);
  assert.equal(committed.args[0]===rolledBack.args[0],false);
  console.log('PASS native wire COMMIT-ACK loss: pg COMMIT failed without acknowledgement, backend committed exactly once and same-scope read recovered one immutable result; pre-COMMIT disconnect rolled all writes back and read remained missing; no approval resend, no live Auth/public transport proof');
 }finally{
  if(proxy)await proxy.close();
  if(client)await client.end().catch(()=>{});
  if(recovered)await recovered.end().catch(()=>{});
 }
}
