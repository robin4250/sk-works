// Disposable native PG17 only. Runtime guards reject every non-fixture URL.
import assert from 'node:assert/strict';
import {validatePayrollScopeFixtureUrl} from './payroll_scope_pg17_database_guard.mjs';
const connectionString=validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL);
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const a=new Client({connectionString}),b=new Client({connectionString}),o=new Client({connectionString});
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001',actor='00000000-0000-0000-0000-000000000002';
const helper='private.payroll_draft_source_fingerprint(uuid,uuid,date)',gate=908172;
const caught=p=>p.then(value=>({value}),error=>({error}));
async function blocked(waiter,holder){
 const limit=Date.now()+7000;
 while(Date.now()<limit){
  const row=(await o.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[waiter])).rows[0];
  if(row?.wait_event_type==='Lock'&&row.blockers.includes(holder))return;
  await new Promise(r=>setTimeout(r,15));
 }
 throw Error('required actual preview lock wait not observed');
}
const draft=async()=>(await o.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
const protectedState=async()=>(await o.query(`select jsonb_build_object(
 'draft',(select to_jsonb(p) from public.payroll_statements p where company_id=$1 and worker_id=$2 and period_start='2026-09-01'),
 'audit',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.payroll_audit x),
 'documents',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from payroll_final_private.documents x),
 'history',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from payroll_final_private.history x),
 'attendance',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.attendance_entries x),
 'settings',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.worker_payroll_settings x)) value`,[cid,wid])).rows[0].value;
async function beginReader(isolation='read committed'){
 await a.query('begin isolation level '+isolation+' read only');
 await a.query("select set_config('request.jwt.claim.sub',$1,true),set_config('fixture.preview_digest_calls','0',true)",[actor]);
 await a.query('set local role authenticated');
}
const preview=ps=>a.query('select public.preview_one_payroll_draft($1,$2,$3,$4,$5) result',[ps.id,ps.revision,cid,wid,'2026-09-01']);
try{
 await Promise.all([a.connect(),b.connect(),o.connect()]);
 assert.equal(Math.floor(Number((await o.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 for(const c of[a,b,o])await c.query("set statement_timeout='20s';set lock_timeout='12s'");
 const pidA=(await a.query('select pg_backend_pid() p')).rows[0].p,pidB=(await b.query('select pg_backend_pid() p')).rows[0].p;
 const original=(await o.query('select pg_get_functiondef($1::regprocedure) d',[helper])).rows[0].d;
 const copy=original.replace('FUNCTION private.payroll_draft_source_fingerprint(', 'FUNCTION private.synthetic_saved_preview_fingerprint(');
 assert.notEqual(copy,original,'canonical helper definition expected');
 await o.query(copy);
 await o.query('revoke all on function private.synthetic_saved_preview_fingerprint(uuid,uuid,date) from public,anon,authenticated');
 // Fixture-only scheduling wrapper: stop on the SECOND digest, after the first
 // digest and current-row reread. set_config is local state, not a database write,
 // so the entire request still runs inside BEGIN READ ONLY.
 await o.query(`create or replace function private.payroll_draft_source_fingerprint(cid uuid,wid uuid,month date)
 returns text language plpgsql volatile security definer set search_path='' as $$
 declare calls integer:=coalesce(nullif(current_setting('fixture.preview_digest_calls',true),''),'0')::integer+1;
 begin
 perform pg_catalog.set_config('fixture.preview_digest_calls',calls::text,true);
 if calls=2 then perform pg_catalog.pg_advisory_xact_lock(${gate});end if;
 return private.synthetic_saved_preview_fingerprint(cid,wid,month);
 end $$`);
 const membership=(await o.query('select to_jsonb(m) value from public.company_members m where company_id=$1 and user_id=$2',[cid,actor])).rows;
 assert.equal(membership.length,1);
 for(const mode of ['source','membership']){
  const before=await protectedState(),ps=await draft();
  await b.query('begin');await b.query('select pg_advisory_xact_lock($1)',[gate]);
  await beginReader();const pending=caught(preview(ps));
  await blocked(pidA,pidB);
  const other='90000000-0000-0000-0000-000000000089';
  if(mode==='source')await b.query('insert into public.trade_companies(id,company_id) values($1,$2)',[other,cid]);
  else assert.equal((await b.query('delete from public.company_members where company_id=$1 and user_id=$2',[cid,actor])).rowCount,1);
  await b.query('commit');
  const result=await pending;
  assert.equal(result.error?.code,mode==='source'?'40001':'42501');
  assert.match(result.error.message,mode==='source'?/preview changed/:/access denied/);
  await a.query('rollback');
  assert.deepEqual(await protectedState(),before,'read-only preview changed protected payroll data');
  if(mode==='source')await o.query('delete from public.trade_companies where id=$1',[other]);
  else await o.query('insert into public.company_members select * from jsonb_populate_record(null::public.company_members,$1::jsonb)',[membership[0].value]);
  console.log(`PASS native read-only preview: observed second-digest lock wait; committed ${mode} change rejected; draft/audit/source/final snapshots unchanged`);
 }
 await o.query(original);
 await o.query('drop function private.synthetic_saved_preview_fingerprint(uuid,uuid,date)');
 const ps=await draft();await beginReader('repeatable read');
 const unsupported=await caught(preview(ps));assert.equal(unsupported.error?.code,'22023');await a.query('rollback');
 await beginReader();const valid=(await preview(ps)).rows[0].result;assert.equal(valid.expected_revision,ps.revision);assert.equal(valid.projected_calculation,null);await a.query('commit');
 console.log('PASS native read-only preview: repeatable-read refused; restored original helper permits valid read-only request; synthetic helpers/JWT only');
}catch(error){console.error(error.message);process.exitCode=1;}
finally{for(const c of[a,b])try{await c.query('rollback');}catch{}await Promise.allSettled([a.end(),b.end(),o.end()]);}
