import assert from 'node:assert/strict';
import {Client} from 'pg';
export async function verifyNotificationFinalizationRace(db,worker,company){
 const connectionString=process.env.SKO_PAYROLL_ATTACHMENT_FIXTURE_URL;
 const clients=[new Client({connectionString}),new Client({connectionString})];
 const [first,second]=clients;
 const owner='00000000-0000-0000-0000-000000000001';
 const read=async()=>(await db.query('select id,revision from public.payroll_statements where worker_id=$1 and period_start=date_trunc(\'month\',now() at time zone \'Asia/Tokyo\')::date',[worker])).rows[0];
 const state=async(client=db)=>JSON.stringify((await client.query(`select * from (
 select 'settings' as source,to_jsonb(t) as value from public.worker_payroll_settings t
 union all select 'payroll',to_jsonb(t) from public.payroll_statements t
 union all select 'reviews',to_jsonb(t) from public.payroll_statement_reviews t
 union all select 'audit',to_jsonb(t) from public.payroll_audit t
 union all select 'issues',to_jsonb(t) from public.generation_setting_issues t
 union all select 'sink',to_jsonb(t) from public.app_notifications t
 union all select 'documents',to_jsonb(t) from payroll_final_private.documents t
 union all select 'history',to_jsonb(t) from payroll_final_private.history t) rows order by source,value::text`)).rows);
 const frozenState=async(client=db)=>JSON.stringify((await client.query(`select * from (
 select 'payroll' as source,to_jsonb(t) as value from public.payroll_statements t
 union all select 'reviews',to_jsonb(t) from public.payroll_statement_reviews t
 union all select 'audit',to_jsonb(t) from public.payroll_audit t
 union all select 'documents',to_jsonb(t) from payroll_final_private.documents t
 union all select 'history',to_jsonb(t) from payroll_final_private.history t) rows order by source,value::text`)).rows);
 const approve=async ps=>{await db.query('delete from public.payroll_statement_reviews where statement_id=$1',[ps.id]);return db.query('insert into public.payroll_statement_reviews(statement_id,reviewer_id,checked_revision,confirmed_revision,confirmed_at) values($1,$2,$3,$3,now())',[ps.id,owner,ps.revision]);};
 const updateSql='update public.worker_payroll_settings set monthly_salary_yen=$1 where company_id=$2 and worker_id=$3';
 async function wait(pid,firstPid,pending){
  const deadline=Date.now()+8000;
  while(Date.now()<deadline){
   const row=(await db.query("select wait_event_type,$2=any(pg_blocking_pids($1)) as first_blocks from pg_stat_activity where pid=$1",[pid,firstPid])).rows[0];
   if(row?.wait_event_type==='Lock'&&row.first_blocks===true)return;
   if(pending.settled)throw new Error('second operation must actually wait for payroll scope');
   await new Promise(resolve=>setTimeout(resolve,20));
  }throw new Error('payroll scope wait not observed');
 }
 function launch(promise){const pending={settled:false};pending.result=promise.then(result=>{pending.settled=true;return{result};},error=>{pending.settled=true;return{error};});return pending;}
 try{
  await Promise.all(clients.map(c=>c.connect()));
  for(const c of clients){await c.query("set statement_timeout='15s'");await c.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);await c.query('set role authenticated');}
  const pid=(await second.query('select pg_backend_pid() as id')).rows[0].id;
  const firstPid=(await first.query('select pg_backend_pid() as id')).rows[0].id;
  const original=await read();await approve(original);
  const sinkBefore=Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n);
  await first.query('begin');await first.query(updateSql,[310000,company,worker]);
  const stale=launch(second.query('select public.finalize_payroll_statement($1,$2,true)',[original.id,original.revision]));
  await wait(pid,firstPid,stale);await first.query('commit');
  const staleResult=await stale.result;assert.ok(staleResult.error);assert.match(staleResult.error.message,/revision conflict/);
  const changed=await read();assert.ok(changed.revision>original.revision);
  assert.ok(Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n)>sinkBefore,'actual settings trigger creates invoice issues and reaches the INSERT sink');
  // Resolving genuine issues makes the next settings update attempt reopen notifications.
  await db.exec('update public.generation_setting_issues set resolved_at=now();create function private.fixture_sink_failure() returns trigger language plpgsql as $$begin raise exception \'fixture sink failure\';end$$;create trigger fixture_sink_failure before insert on public.app_notifications for each row execute function private.fixture_sink_failure()');
  const beforeFailure=await state();await assert.rejects(first.query(updateSql,[315000,company,worker]),/fixture sink failure/);
  assert.equal(await state(),beforeFailure,'actual sink failure rolls back settings, payroll, issue lifecycle and frozen sources together');
  await db.exec('drop trigger fixture_sink_failure on public.app_notifications');
  const beforeFutureSink=Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n);
  await approve(changed);
  await first.query('begin');assert.equal((await first.query('select public.finalize_payroll_statement($1,$2,true) as result',[changed.id,changed.revision])).rows[0].result.finalized,true);
  await first.query('reset role');const captured=await frozenState(first);await first.query('set role authenticated');
  const blocked=launch(second.query(updateSql,[320000,company,worker]));await wait(pid,firstPid,blocked);await first.query('commit');
  const blockedResult=await blocked.result;assert.equal(blockedResult.error,undefined);assert.equal(blockedResult.result.rowCount,1,'future default settings remain editable after finalization');
  assert.equal(await frozenState(),captured,'successful future default edit preserves every captured payroll/document/history/review/audit row');
  assert.equal(Number((await db.query("select value#>>'{conditions,settings,monthly_salary_yen}' as n from payroll_final_private.documents where statement_id=$1",[changed.id])).rows[0].n),310000,'snapshot keeps finalized conditions, independently of current default');
  assert.equal(Number((await db.query('select monthly_salary_yen as n from public.worker_payroll_settings where worker_id=$1',[worker])).rows[0].n),320000);
  assert.ok(Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n)>beforeFutureSink,'future default update may reopen actual invoice issues and append notifications without touching frozen payroll');
  assert.ok(Number((await db.query("select count(*) as n from public.generation_setting_issues where issue_key like 'invoice-%' and resolved_at is null")).rows[0].n)>0);
  console.log('PASS native PG17 actual generation-settings sink/finalization both orders: real scope waits, stale finalization rejection, future default update with frozen source preservation and eight-table sink failure rollback');
 }finally{await Promise.all(clients.map(async c=>{await c.query('rollback').catch(()=>{});await c.end();}));}
}
