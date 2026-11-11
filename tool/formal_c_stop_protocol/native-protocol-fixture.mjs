// Generic protocol observation ONLY. Never executes or proves safe deployment
// of the retained C capsule. Its old writers do not implement this fixture gate.
import assert from 'node:assert/strict';
const url=new URL(process.env.SKO_STOP_FIXTURE_URL??'');
if(!['postgres:','postgresql:'].includes(url.protocol)||url.hostname!=='127.0.0.1'||url.port!=='5432'
 ||url.username!=='postgres'||url.password!=='fixture-only'||url.pathname!=='/sko_stop_fixture'||url.search)throw Error('dedicated localhost fixture required');
const driver=await import(process.argv[2]);
const Client=driver.Client??driver.default?.Client;
if(typeof Client!=='function')throw Error('fixture pg Client missing');
const clients=[];let opened=0,closed=0,cleanupCalls=0,cleanupFailures=0;
const connect=async()=>{const c=new Client({connectionString:url.toString(),connectionTimeoutMillis:3000,query_timeout:10000});const entry={client:c,connected:false};clients.push(entry);await c.connect();entry.connected=true;opened++;await c.query("set statement_timeout='8s';set lock_timeout='4s'");return c;};
let a,b,observer;
const scalar=async(c,sql,args=[])=>Object.values((await c.query(sql,args)).rows[0])[0];
let realWaits=0;
async function waitForLock(pid){const until=Date.now()+3000;while(Date.now()<until){const row=(await observer.query('select wait_event_type,state from pg_stat_activity where pid=$1',[pid])).rows[0];if(row?.wait_event_type==='Lock'&&row.state==='active'){realWaits++;return;}await new Promise(resolve=>setTimeout(resolve,20));}throw Error('real native blocking not observed');}
async function rejectWithoutMutation(fn){const before=await scalar(a,'select count(*)::int from c_stop_fixture.events');await assert.rejects(fn,error=>error.code==='55000');assert.equal(await scalar(a,'select count(*)::int from c_stop_fixture.events'),before);}
try{
 a=await connect();b=await connect();observer=await connect();
 // All names, rows, gates and claims below are disposable simulation artifacts.
 await a.query(`create schema c_stop_fixture;
 create table c_stop_fixture.admission(id int primary key check(id=1),open boolean not null,epoch int not null);
 insert into c_stop_fixture.admission values(1,true,1);
 create table c_stop_fixture.events(id bigint generated always as identity primary key,kind text not null);
 create function c_stop_fixture.guarded_writer(pause boolean default false)returns text language plpgsql as $$begin
 if not(select open from c_stop_fixture.admission where id=1)then raise exception 'admission closed'using errcode='55000';end if;
 if pause then perform pg_advisory_xact_lock(73001501);end if;
 insert into c_stop_fixture.events(kind)values('admitted');return 'admitted';end$$;
 create function c_stop_fixture.unsafe_old_writer()returns text language plpgsql as $$begin
 insert into c_stop_fixture.events(kind)values('old');return 'old';end$$;
 create function c_stop_fixture.cached_caller()returns text language plpgsql as $$begin return c_stop_fixture.unsafe_old_writer();end$$;`);
 const pid=await scalar(b,'select pg_backend_pid()');
 // Already-admitted operation must drain; closing a new gate cannot cancel it.
 await a.query('select pg_advisory_lock(73001501)');
 let active=b.query('select c_stop_fixture.guarded_writer(true) value');active.catch(()=>{});
 try{
  await waitForLock(pid);
  await a.query('update c_stop_fixture.admission set open=false,epoch=epoch+1 where id=1');
  await rejectWithoutMutation(()=>a.query('select c_stop_fixture.guarded_writer(false)'));
  assert.equal(await scalar(observer,'select state from pg_stat_activity where pid=$1',[pid]),'active');
  // An operator reporting drained here would be false: the pre-closure writer waits.
  assert.equal(await scalar(a,'select count(*)::int from c_stop_fixture.events'),0);
 }finally{await a.query('select pg_advisory_unlock(73001501)');}
 assert.equal((await active).rows[0].value,'admitted');
 assert.equal(await scalar(a,'select count(*)::int from c_stop_fixture.events'),1);
 // A new advisory gate is not acquired by legacy callers: actual bypass proof.
 await a.query('select pg_advisory_lock(73001502)');
 try{assert.equal(await scalar(b,'select c_stop_fixture.unsafe_old_writer()'),'old');}
 finally{await a.query('select pg_advisory_unlock(73001502)');}
 // Observe prepared SQL and a warmed PL/pgSQL call across a function rename.
 // We record the native outcome; we never assume rename invalidates every plan.
 await b.query('prepare before_rename as select c_stop_fixture.unsafe_old_writer() value');
 assert.equal(await scalar(b,'select c_stop_fixture.cached_caller()'),'old');
 await a.query(`begin;
 alter function c_stop_fixture.unsafe_old_writer()rename to retained_old_writer;
 create function c_stop_fixture.unsafe_old_writer()returns text language plpgsql as $$begin
 if not(select open from c_stop_fixture.admission where id=1)then raise exception 'admission closed'using errcode='55000';end if;
 insert into c_stop_fixture.events(kind)values('new');return 'new';end$$;
 commit;`);
 const observe=async sql=>{try{return {value:await scalar(b,sql)};}catch(error){return {code:error.code};}};
 const prepared=await observe('execute before_rename'),cached=await observe('select c_stop_fixture.cached_caller()');
 for(const value of [prepared,cached])assert.ok(value.value==='old'||value.code==='55000','unexpected native cache observation');
 await rejectWithoutMutation(()=>a.query('select c_stop_fixture.unsafe_old_writer()'));
 // Old OID/alias remains executable unless real admission controls every caller.
 assert.equal(await scalar(b,'select c_stop_fixture.retained_old_writer()'),'old');
 // Idle transactions are a separate drain blocker; no forced abort is used.
 await b.query('begin');await b.query('select 1');
 assert.equal(await scalar(observer,'select state from pg_stat_activity where pid=$1',[pid]),'idle in transaction');
 await b.query('rollback');
 // Prepared transactions must be checked separately, even when none exist.
 const preparedXacts=await scalar(observer,"select count(*)::int from pg_prepared_xacts where database=current_database()");assert.equal(preparedXacts,0);
 console.log(JSON.stringify({generic_protocol_only:true,retained_C_executed:false,production_changed:false,
 real_waits:realWaits,old_admitted_writer_drained:true,new_gate_does_not_protect_legacy:true,
 native_prepared_after_rename:prepared,native_cached_plpgsql_after_rename:cached,
 retained_alias_bypasses_fixture_gate:true,idle_transaction_detected:true,prepared_transactions_checked:true,
 unknown_ingress_owner_proven:false,real_queue_drained:false,pool_recycled:false,formal_C_deployable:false}));
}finally{
 for(const entry of clients.reverse()){const c=entry.client;if(entry.connected){try{await c.query('rollback');}catch{}}try{cleanupCalls++;await c.end();if(entry.connected)closed++;}catch{cleanupFailures++;}}
 console.log(JSON.stringify({fixture_clients_allocated:clients.length,fixture_cleanup_calls:cleanupCalls,fixture_cleanup_failures:cleanupFailures,fixture_connections_opened:opened,fixture_connections_closed:closed,production_changed:false}));
 assert.equal(cleanupFailures,0,'fixture cleanup failure');assert.equal(closed,opened,'fixture connections not closed');
}
