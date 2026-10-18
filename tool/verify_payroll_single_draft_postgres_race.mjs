// Native PG17 only; prepared synthetic fixture. Never consumes real checkpoints.
import assert from 'node:assert/strict';
import {validatePayrollScopeFixtureUrl} from './payroll_scope_pg17_database_guard.mjs';
const connectionString=validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL);
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const a=new Client({connectionString,application_name:'sko-one-draft-A'}),b=new Client({connectionString,application_name:'sko-one-draft-B'}),o=new Client({connectionString,application_name:'sko-one-draft-observer'});
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',actor='00000000-0000-0000-0000-000000000002';
const helper='private.payroll_draft_source_fingerprint(uuid,uuid,date)',gate=908171;
const draft=async()=>(await o.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
async function begin(c,isolation='read committed'){await c.query('begin isolation level '+isolation);await c.query("select set_config('request.jwt.claim.sub',$1,true)",[actor]);await c.query('set local role authenticated');}
const caught=p=>p.then(value=>({value}),error=>({error}));
async function blocked(waiter,holder){const limit=Date.now()+7000;while(Date.now()<limit){const row=(await o.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[waiter])).rows[0];if(row?.wait_event_type==='Lock'&&row.blockers.includes(holder))return;await new Promise(r=>setTimeout(r,15));}throw Error('required actual lock wait not observed');}
try{
 await Promise.all([a.connect(),b.connect(),o.connect()]);assert.equal(Math.floor(Number((await o.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 for(const c of[a,b,o])await c.query("set statement_timeout='20s';set lock_timeout='12s'");
 const pidA=(await a.query('select pg_backend_pid() p')).rows[0].p,pidB=(await b.query('select pg_backend_pid() p')).rows[0].p;
 const originalHelper=(await o.query('select pg_get_functiondef($1::regprocedure) d',[helper])).rows[0].d;
 // A real statement UPDATE from existing sync pauses after the before-digest.
 await o.query(`create function public.synthetic_draft_race_gate() returns trigger language plpgsql as $$begin perform pg_advisory_xact_lock(${gate});return new;end$$;create trigger zzzz_synthetic_draft_race_gate before update on public.payroll_statements for each row execute function public.synthetic_draft_race_gate()`);
 for(const mode of ['stable','volatile']){
  await o.query(`alter function ${helper} ${mode}`);
  const ps=await draft(),source=(await o.query('select private.payroll_draft_source_fingerprint($1,$2,$3) h',[cid,wid,'2026-09-01'])).rows[0].h;
  await b.query('begin');await b.query('select pg_advisory_xact_lock($1)',[gate]);
  await begin(a);const pending=caught(a.query('select public.recalculate_one_payroll_draft($1,$2,$3,$4,$5,true,$6) result',[ps.id,ps.revision,cid,wid,'2026-09-01',source]));
  await blocked(pidA,pidB);
  // Deliberately non-cooperative synthetic source writer; no app-lock shortcut.
  const other='90000000-0000-0000-0000-000000000088';
  await b.query('insert into public.trade_companies(id,company_id) values($1,$2)',[other,cid]);await b.query('commit');
  const result=await pending;
  if(result.error){assert.equal(result.error.code,'40001');assert.equal(result.error.message,'payroll source changed');await a.query('rollback');assert.deepEqual(await draft(),ps);console.log(`PASS native ${mode}: observed statement lock wait; other connection source commit detected and full draft rollback`);}
  else {await a.query('commit');assert.equal(mode,'stable','VOLATILE must detect committed drift');console.log('OBSERVED native stable control missed concurrent committed source drift');}
  await o.query('delete from public.trade_companies where id=$1',[other]);
 }
 await o.query(originalHelper);
 await o.query('drop trigger zzzz_synthetic_draft_race_gate on public.payroll_statements;drop function public.synthetic_draft_race_gate()');
 // Existing public unit-conditions API/refresh commits before the waiting draft CAS can run.
 const ps=await draft(),source=(await o.query('select private.payroll_draft_source_fingerprint($1,$2,$3) h',[cid,wid,'2026-09-01'])).rows[0].h;
 await b.query('begin');await b.query('select 1 from public.workers where id=$1 for update',[wid]);
 await begin(a);const stale=caught(a.query('select public.recalculate_one_payroll_draft($1,$2,$3,$4,$5,true,$6)',[ps.id,ps.revision,cid,wid,'2026-09-01',source]));await blocked(pidA,pidB);
 await b.query("select set_config('request.jwt.claim.sub',$1,true)",[actor]);await b.query('set local role authenticated');
 await b.query("select public.save_payroll_unit_conditions($1,$2,'2026-09-01',0,$3::jsonb)",[cid,wid,JSON.stringify([{section:'earning',unit:'month',name:'Synthetic CAS source',rate_yen:1}])]);await b.query('commit');const rejected=await stale;assert.equal(rejected.error?.code,'40001');assert.match(rejected.error.message,/revision or scope changed/);await a.query('rollback');const current=await draft();assert.ok(current.revision>ps.revision);
 await begin(a,'repeatable read');const repeatable=await caught(a.query('select public.recalculate_one_payroll_draft($1,$2,$3,$4,$5,true,$6)',[ps.id,current.revision,cid,wid,'2026-09-01',source]));assert.equal(repeatable.error?.code,'22023');assert.match(repeatable.error.message,/read committed/);await a.query('rollback');
 console.log('PASS native observed worker-lock wait, committed revision CAS rejection, repeatable-read refusal; synthetic PG17 only');
} catch(error){console.error(error.message);process.exitCode=1;}finally{for(const c of[a,b])try{await c.query('rollback');}catch{}await Promise.allSettled([a.end(),b.end(),o.end()]);}
