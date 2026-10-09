import assert from 'node:assert/strict';
import {Client} from 'pg';
export async function verifyNotificationFinalizationRace(db,worker){
 const connectionString=process.env.SKO_PAYROLL_ATTACHMENT_FIXTURE_URL;
 const clients=[new Client({connectionString}),new Client({connectionString})];
 const [first,second]=clients;
 const company='10000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001';
 const read=async()=>(await db.query('select id,revision from public.payroll_statements where worker_id=$1 and period_start=date_trunc(\'month\',now() at time zone \'Asia/Tokyo\')::date',[worker])).rows[0];
 const state=async()=>JSON.stringify((await db.query(`select * from (
 select 'settings' as source,to_jsonb(t) as value from public.worker_payroll_settings t
 union all select 'payroll',to_jsonb(t) from public.payroll_statements t
 union all select 'issues',to_jsonb(t) from public.generation_setting_issues t
 union all select 'sink',to_jsonb(t) from public.app_notifications t
 union all select 'documents',to_jsonb(t) from payroll_final_private.documents t
 union all select 'history',to_jsonb(t) from payroll_final_private.history t) rows order by source,value::text`)).rows);
 const approve=async ps=>{await db.query('delete from public.payroll_statement_reviews where statement_id=$1',[ps.id]);return db.query('insert into public.payroll_statement_reviews(statement_id,reviewer_id,checked_revision,confirmed_revision,confirmed_at) values($1,$2,$3,$3,now())',[ps.id,owner,ps.revision]);};
 const updateSql='update public.worker_payroll_settings set monthly_salary_yen=$1 where company_id=$2 and worker_id=$3';
 async function wait(pid,pending){
  const deadline=Date.now()+8000;
  while(Date.now()<deadline){
   const row=(await db.query("select wait_event_type from pg_stat_activity where pid=$1",[pid])).rows[0];
   if(row?.wait_event_type==='Lock')return;
   if(pending.settled)throw new Error('second operation must actually wait for payroll scope');
   await new Promise(resolve=>setTimeout(resolve,20));
  }throw new Error('payroll scope wait not observed');
 }
 function launch(promise){const pending={settled:false};pending.result=promise.then(result=>{pending.settled=true;return{result};},error=>{pending.settled=true;return{error};});return pending;}
 try{
  await Promise.all(clients.map(c=>c.connect()));
  for(const c of clients){await c.query("set statement_timeout='15s'");await c.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);await c.query('set role authenticated');}
  const pid=(await second.query('select pg_backend_pid() as id')).rows[0].id;
  const original=await read();await approve(original);
  const sinkBefore=Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n);
  await first.query('begin');await first.query(updateSql,[310000,company,worker]);
  const stale=launch(second.query('select public.finalize_payroll_statement($1,$2,true)',[original.id,original.revision]));
  await wait(pid,stale);await first.query('commit');
  const staleResult=await stale.result;assert.ok(staleResult.error);assert.match(staleResult.error.message,/revision conflict/);
  const changed=await read();assert.ok(changed.revision>original.revision);
  assert.ok(Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n)>sinkBefore,'actual settings trigger creates invoice issues and reaches the INSERT sink');
  // Resolving genuine issues makes the next settings update attempt reopen notifications.
  await db.exec('update public.generation_setting_issues set resolved_at=now();create function private.fixture_sink_failure() returns trigger language plpgsql as $$begin raise exception \'fixture sink failure\';end$$;create trigger fixture_sink_failure before insert on public.app_notifications for each row execute function private.fixture_sink_failure()');
  const beforeFailure=await state();await assert.rejects(first.query(updateSql,[315000,company,worker]),/fixture sink failure/);
  assert.equal(await state(),beforeFailure,'actual sink failure rolls back settings, payroll, issue lifecycle and frozen sources together');
  await db.exec('drop trigger fixture_sink_failure on public.app_notifications');
  await approve(changed);
  await first.query('begin');assert.equal((await first.query('select public.finalize_payroll_statement($1,$2,true) as result',[changed.id,changed.revision])).rows[0].result.finalized,true);
  const blocked=launch(second.query(updateSql,[320000,company,worker]));await wait(pid,blocked);await first.query('commit');
  const blockedResult=await blocked.result;assert.ok(blockedResult.error);assert.match(blockedResult.error.message,/finalized payroll requires an explicit correction/);
  assert.equal(Number((await db.query('select monthly_salary_yen as n from public.worker_payroll_settings where worker_id=$1',[worker])).rows[0].n),310000);
  console.log('PASS native PG17 actual generation-settings sink/finalization both orders: real scope waits, stale finalization rejection, source edit rejection after frozen capture and complete sink failure rollback');
 }finally{await Promise.all(clients.map(async c=>{await c.query('rollback').catch(()=>{});await c.end();}));}
}
