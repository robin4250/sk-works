// Native loopback PostgreSQL17 only. Synthetic identities and saved candidate.
import assert from 'node:assert/strict';
import {PGlite} from './worker_document_change_native_pg17_runtime.mjs';
import {validateWorkerDocumentFixtureUrl} from './worker_document_change_pg17_guard.mjs';
import {setupWorkerDocumentChangeFixture,uid,company,requirement,owner,reviewer} from './worker_document_change_fixture_setup.mjs';
const db=new PGlite();
const pg=(await import(process.env.SKO_DOCUMENT_PG_MODULE)).default;
const connectionString=validateWorkerDocumentFixtureUrl(process.env.SKO_DOCUMENT_CHANGE_FIXTURE_URL);
const secondReviewer=uid(8);
const a=new pg.Client({connectionString,application_name:'document-race-a'});
const b=new pg.Client({connectionString,application_name:'document-race-b'});
const actor=async(client,id)=>{await client.query('reset role');await client.query("select set_config('fixture.uid',$1,false)",[id]);await client.query('set role authenticated');};
const rpc=async(client,action,data)=>(await client.query('select public.worker_document_change($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
async function fixture(n,requests=1) {
 await db.exec('reset role');
 const w=uid(100+n),t=uid(200+n);
 const photo=`${company}/${w}/${requirement}/own-upload/front.jpg`;
 await db.query("insert into storage.objects(bucket_id,name) values('worker-documents',$1)",[photo]);
 await db.query('insert into public.workers values($1,$2,$3)',[w,company,owner]);
 await actor(db,owner);
 await db.query("insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,updated_by) values($1,$2,$3,$4,$5)",[t,company,w,requirement,owner]);
 await db.query("update public.worker_document_statuses set status='submitted',attachment_path=$1,notes='original',updated_by=$2 where id=$3",[photo,owner,t]);
 const original=(await db.query('select * from public.worker_document_statuses where id=$1',[t])).rows[0];
 const ids=[];
 for(let i=0;i<requests;i++) {
  const id=uid(300+n*10+i);ids.push(id);
  await rpc(db,'prepare',{request_id:id,status_id:t,expected_updated_at:original.updated_at,proposed:{attachment_paths:[photo],expires_at:'2027-01-01',notes:`approved-${i}`}});
  await rpc(db,'submit',{request_id:id});
 }
 await db.exec('reset role');
 const history=Number((await db.query('select count(*) n from public.worker_document_status_history where source_status_id=$1',[t])).rows[0].n);
 return {target:t,ids,history};
}
// Query a session PID before starting its blocked operation; the client queue
// cannot service pg_backend_pid while its preceding query is waiting.
async function competing(client,action,id) {
 const pid=(await client.query('select pg_backend_pid() pid')).rows[0].pid;
 const result=rpc(client,action,{request_id:id}).then(value=>({value}),error=>({error}));
 for(let i=0;i<100;i++) {
  const state=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0];
  if(state?.wait_event_type==='Lock')return {result};
  await new Promise(resolve=>setTimeout(resolve,20));
 }
 throw Error('No real lock wait observed');
}
async function once(f) {
 assert.equal(Number((await db.query('select count(*) n from public.worker_document_status_history where source_status_id=$1',[f.target])).rows[0].n),f.history+1);
 assert.equal(Number((await db.query('select count(*) n from private.worker_document_apply_tickets')).rows[0].n),0);
}
try {
 await setupWorkerDocumentChangeFixture(db);
 await db.query('insert into auth.users values($1)',[secondReviewer]);
 await db.query('insert into public.company_members values($1,$2,$3)',[company,secondReviewer,'admin']);
 await a.connect();await b.connect();
 for(const c of [a,b])await c.query("set statement_timeout='15s';set lock_timeout='10s'");
 let f=await fixture(1);
 await actor(a,reviewer);await actor(b,secondReviewer);
 await a.query('begin');await b.query('begin');
 await rpc(a,'approve',{request_id:f.ids[0]});
 // Hold the transaction open while the second reviewer contends for same request.
 const same=await competing(b,'approve',f.ids[0]);
 await a.query('commit');
 assert.equal((await same.result).value?.status,'approved');await b.query('commit');await once(f);
 console.log('PASS same-request two-reviewer approval serializes and writes official/history once');
 f=await fixture(2,2);await actor(a,reviewer);await actor(b,secondReviewer);
 await a.query('begin');await b.query('begin');await rpc(a,'approve',{request_id:f.ids[0]});
 const different=await competing(b,'approve',f.ids[1]);await a.query('commit');
 assert.equal((await different.result).error?.code,'40001');await b.query('rollback');await once(f);
 assert.equal((await db.query('select status from private.worker_document_changes where id=$1',[f.ids[1]])).rows[0].status,'pending');
 console.log('PASS competing requests from same snapshot: one apply, stale request remains pending');
 f=await fixture(3);await actor(a,reviewer);await actor(b,secondReviewer);
 await a.query('begin');await b.query('begin');
 await a.query("update public.worker_document_statuses set status='verified',original_verified=true,updated_by=$1,updated_at=clock_timestamp() where id=$2",[reviewer,f.target]);
 const stale=await competing(b,'approve',f.ids[0]);await a.query('commit');
 assert.equal((await stale.result).error?.code,'40001');await b.query('rollback');
 const official=(await db.query('select * from public.worker_document_statuses where id=$1',[f.target])).rows[0];
 assert.equal(official.notes,'original');assert.equal(official.status,'verified');assert.equal(official.original_verified,true);await once(f);
 assert.equal((await db.query('select status from private.worker_document_changes where id=$1',[f.ids[0]])).rows[0].status,'pending');
 console.log('PASS concurrent verification update: stale approval refuses CAS without lost update');
} finally {
 for(const c of [a,b]){try{await c.query('rollback');}catch{}try{await c.end();}catch{}}
 await db.close();
}
