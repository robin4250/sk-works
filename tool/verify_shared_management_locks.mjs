// Exact actual manager writer + pinned normalizer + existing financial pipeline.
// Identity/permission/table surroundings are explicitly synthetic, no real auth.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const base=await readFile('tool/verify_shared_group_lock.mjs','utf8');
// Add to the inner shared proof before the synthetic closing module teardown.
const marker="const beforeCommit=";
assert.equal(base.split(marker).length,2);
const setup=String.raw`
const managerMarker=" await exec('drop function checkout_shared_hours_private.prepare_supervisor(uuid,text);";
assert.equal(base.split(managerMarker).length,2);
const managerUnit=String.raw\u0060
 await exec("alter table public.company_members add column if not exists role text default 'manager';alter table public.workers add column if not exists status text default 'active';alter table public.attendance_verifications add column if not exists verification_mode text;alter table public.attendance_verifications add column if not exists proximity_status text;alter table public.attendance_verifications add column if not exists note text;alter table public.attendance_verifications add column if not exists created_by uuid;create table if not exists public.attendance_correction_items(id uuid,attendance_entry_id uuid);create table if not exists public.paid_leave_requests(id uuid,batch_id uuid,company_id uuid,worker_id uuid,requested_by uuid,leave_date date,reason text,status text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);create or replace function public.current_feature_permissions() returns jsonb language sql stable as $$select jsonb_build_object('can_manage_attendance',current_setting('fixture.manager',true)='on')$$;");
 // The parent already creates a deliberately minimal four-column leave table.
 // Complete the observed fifteen-column shape in one step, without replacing
 // that table, its existing rows, the actual writer, or financial assertions.
 await exec("alter table public.paid_leave_requests add column if not exists id uuid,add column if not exists batch_id uuid,add column if not exists company_id uuid,add column if not exists worker_id uuid,add column if not exists requested_by uuid,add column if not exists leave_date date,add column if not exists reason text,add column if not exists status text,add column if not exists reviewed_by uuid,add column if not exists reviewed_at timestamptz,add column if not exists review_note text,add column if not exists day_before_notified_at timestamptz,add column if not exists same_day_notified_at timestamptz,add column if not exists created_at timestamptz,add column if not exists updated_at timestamptz;");
 const managerFixture=JSON.parse(await readFile('tool/security/shared_management_source_fixture.json','utf8'));
 await exec(managerFixture.definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='public.force_manage_attendance(text,jsonb)'::regprocedure"),managerFixture.source_md5,'Exact actual manager source loaded unchanged before lock prefix');
 await exec(await readFile('docs/candidates/shared_daily_report_management_locks.sql.review-only','utf8'));
 await exec("select set_config('fixture.manager','on',false)");
 await client.query("update public.company_members set role='manager' where company_id=$1 and user_id=$2",[A,memberC]);
 const managedBatch=JSON.stringify([reportWorker,W2].map(workerId=>({worker_id:workerId,date:'2026-11-02',mode:'work',site_id:SITE,man_days:1,clock_in:'08:00',clock_out:'17:00',allowance_names:[]})));
 eq(await sharedCall(memberC,sidC,'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',managedBatch]),2,'Original actual manager authorizes and executes prepared two-worker batch');
 eq(await q("select count(*)::int v from public.attendance_verifications where company_id=$1 and work_date='2026-11-02'",[A]),4,'Prepared batch retains both real entered start/end pairs');
 eq(await q("select count(*)::int v from public.attendance_entries where company_id=$1 and work_date='2026-11-02'",[A]),2,'Original financial writer creates one attendance per worker');
 const managerRace=new pg.Client({connectionString:destination.href,connectionTimeoutMillis:5000});await managerRace.connect();
 try {
  await managerRace.query('begin');
  await managerRace.query("select pg_advisory_xact_lock(hashtextextended(jsonb_build_array($1::uuid,'2026-11-04'::date,$2::uuid,null)::text,0))",[A,SITE]);
  await managerRace.query("insert into public.daily_reports(id,company_id,site_id,report_date,status,work_description,created_by,updated_by) values($1,$2,$3,'2026-11-04','draft','待機中に作成された原本',$4,$4)",[id(8690),A,SITE,U]);
  const waitingPid=await q('select pg_backend_pid() v');
  await exec("set statement_timeout='4s'");
  const blockedWrite=sharedCall(memberC,sidC,'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',JSON.stringify([{worker_id:reportWorker,date:'2026-11-04',mode:'work',site_id:SITE,man_days:1,clock_in:'08:00',clock_out:'17:00',allowance_names:[]}])]).then(value=>({value}),error=>({error}));
  let waiting=false;
  for(let attempt=0;attempt<50;attempt++){
   await managerRace.query('select pg_stat_clear_snapshot()');
   const state=await managerRace.query("select wait_event_type='Lock' as waiting from pg_stat_activity where pid=$1",[waitingPid]);
   if(state.rows[0]?.waiting===true){waiting=true;break;}
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  await managerRace.query('commit');
  const blockedResult=await blockedWrite;
  assert.equal(waiting,true,'Manager waits after canonical scopes and before its group lock');
  assert.match(blockedResult.error?.message??'',/shared_group_management_sources_changed/);
  eq(await q("select work_description v from public.daily_reports where id=$1",[id(8690)]),'待機中に作成された原本','Group-wait source expansion is rejected without rewriting the new report');
  eq(await q("select count(*)::int v from public.attendance_entries where company_id=$1 and work_date='2026-11-04'",[A]),0,'Stale manager batch produces no attendance or payroll projection');
 } finally {await managerRace.query('rollback');await managerRace.end();await exec('reset statement_timeout');}
 await exec("select set_config('fixture.manager','off',false)");
 await reject(()=>sharedCall(memberC,sidC,'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',managedBatch]),/permission required/);
\u0060;
base=base.replace(managerMarker,()=>managerUnit+managerMarker);
`;
const generated=base.replace(marker,()=>setup.replaceAll('\\u0060','`')+marker);
const folder=await mkdtemp(join(tmpdir(),'shared-management-proof-'));
try{const file=join(folder,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 if(result.status===0)console.log(JSON.stringify({pass:true,actual_manager_lock_prefix:true,production_changed:false}));
}finally{await rm(folder,{recursive:true,force:true});}
