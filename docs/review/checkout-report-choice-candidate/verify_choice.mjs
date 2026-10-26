// Disposable PG17 only. Synthetic authorization; no real JWT/provider claim.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
assert.equal(process.env.CI,'true');
const url=new URL(process.env.SKO_REPORT_FIXTURE_URL);
assert.equal(url.hostname,'127.0.0.1');assert.equal(url.username,'postgres');
assert.equal(url.password,'fixture-only');assert.equal(url.pathname,'/sko_report_registration_fixture');
assert.equal(url.protocol,'postgresql:');assert.equal(url.port,'5432');assert.equal(process.platform,'linux');
assert.ok(!Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
const pg=(await import(process.argv[2])).default;
const db=new pg.Client({connectionString:url.href});await db.connect();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const q=async(s,p=[]) => {
 const publicReader=/select public\.(read_pending_checkout_report_registration|read_checkout_report_registration_notification|choose_checkout_report_registration)\(/.test(s);
 if(publicReader)await db.query('set role authenticated');
 try{return(await db.query(s,p)).rows[0]?.v;}finally{if(publicReader)await db.query('reset role');}
};
try {
 const version=Number(await q("select current_setting('server_version_num') v"));assert.ok(version>=170000&&version<180000);
 assert.equal(await q("select count(*)::int v from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'"),0);
 await db.query(`create role anon; create role authenticated; create role service_role; create schema auth;create schema private;
 alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('fixture.claims',true),'')::jsonb,jsonb_build_object('role','authenticated','sub',current_setting('fixture.actor',true),'session_id',coalesce(nullif(current_setting('fixture.session',true),''),'00000000-0000-0000-0000-000000000080'),'is_anonymous',false))$$;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(nullif(current_setting('fixture.account',true),'')::boolean,true)$$;
 create table companies(id uuid primary key);
 create table workers(id uuid primary key,company_id uuid,user_id uuid,status text default 'active');
 create table company_members(company_id uuid,user_id uuid,primary key(company_id,user_id));
 create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,event_type text,confirmed_at timestamptz,work_date date,source_clock_in_id uuid,daily_report_id uuid,vehicle_id uuid);
 create table daily_reports(id uuid primary key,company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,status text,updated_at timestamptz,work_description text,representative_signer_name text,representative_signature_json jsonb,supervisor_signer_name text,supervisor_signature_json jsonb,signed_at timestamptz,signature_json jsonb);
 create table daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric default 0,early_hours numeric default 0,night_hours numeric default 0,work_category text default 'day',vehicle_id uuid,odometer_km numeric,vehicle_meter_event_id uuid,vehicle_meter_source_clock_in_id uuid,route_assignment_id uuid,previous_odometer_km numeric,trip_distance_km numeric);
 create table vehicles(id uuid,company_id uuid,is_active boolean default true);
 create table vehicle_usage_claims(source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,ended_at timestamptz);
 create table vehicle_meter_events(id uuid,source_clock_in_id uuid,company_id uuid,driver_worker_id uuid,vehicle_id uuid,work_date date,previous_km numeric,current_km numeric,distance_km numeric);
 create table private.vehicle_usage_rollout(company_id uuid,enabled boolean);
 create table private.vehicle_meter_report_links(report_id uuid,worker_id uuid,source_clock_in_id uuid,event_id uuid);
 create table attendance_entries(id uuid,source_report_id uuid,company_id uuid,worker_id uuid,work_date date,site_id uuid,route_assignment_id uuid,base_man_days numeric,overtime_hours numeric,early_hours numeric,night_hours numeric,work_category text);
 create table payroll_statements(company_id uuid,worker_id uuid,period_start date,period_end date,automatic_calculation boolean,workflow_state text,updated_at timestamptz,detail jsonb,calculation_blocked boolean default false);
 create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid,read_at timestamptz);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$declare n uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id) values($1,$2,$3,$4,$5,$6,$7) returning id into n;return n;end$$;`);
 const meterSource=await readFile('supabase/migrations/20261008162618_attach_vehicle_meter_to_report.sql','utf8');
 const originalGuard=/create function private\.guard_linked_vehicle_meter_report\(\)[\s\S]*?end \$\$;/.exec(meterSource)?.[0];assert.ok(originalGuard);
 await db.query(originalGuard);
 const scopeSource=await readFile('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','utf8');
 const originalLock=/create function payroll_scope_private\.lock_scopes\([\s\S]*?end \$\$;/.exec(scopeSource)?.[0];assert.ok(originalLock);
 await db.query('create schema payroll_scope_private');await db.query(originalLock);
 await db.query('revoke all on function payroll_scope_private.lock_scopes(jsonb,boolean) from public,anon,authenticated');
 await db.query('revoke all on function private.guard_linked_vehicle_meter_report() from public,anon,authenticated');
 await db.query('create trigger linked_vehicle_meter_report_guard before update on daily_reports for each row execute function private.guard_linked_vehicle_meter_report()');
 await db.query(await readFile('docs/candidates/checkout_report_registration.sql.review-only','utf8'));
 const validatorSql=await readFile('docs/candidates/checkout_report_registration_validators.sql.review-only','utf8');
 await db.query('alter function private.guard_linked_vehicle_meter_report() set search_path=public');
 await assert.rejects(()=>db.query(validatorSql),/vehicle meter guard source prerequisite differs/);await db.query('rollback');
 await db.query("alter function private.guard_linked_vehicle_meter_report() set search_path=''");
 for(const p of ['validators','reminders','schedule'])await db.query(await readFile(`docs/candidates/checkout_report_registration_${p}.sql.review-only`,'utf8'));
 await db.query('select set_config(\'fixture.actor\',$1,false)',[id(2)]);
 await db.query('insert into auth.users(id) values($1),($2)',[id(2),id(99)]);
 await db.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$4)',[id(80),id(2),id(81),id(99)]);
 for(const signature of ['public.read_pending_checkout_report_registration()','public.read_checkout_report_registration_notification(uuid)']){
  assert.equal(await q('select has_function_privilege(\'service_role\',$1,\'EXECUTE\') v',[signature]),false,'Default service ACL explicitly revoked');
  assert.equal(await q('select has_function_privilege(\'anon\',$1,\'EXECUTE\') v',[signature]),false,'Default anon ACL explicitly revoked');
 }

 await db.query('insert into companies values($1);',[id(1)]);
 await db.query('insert into private.vehicle_usage_rollout values($1,true)',[id(1)]);
 await db.query('insert into workers(id,company_id,user_id) values($1,$2,$3)',[id(3),id(1),id(2)]);
 await db.query('insert into company_members values($1,$2)',[id(1),id(2)]);
 await db.query("insert into checkout_report_registration_private.rollout values($1,'2026-10-01',false)",[id(1)]);
 await db.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-24 08:00Z','2026-10-24',null,null,null),($2,$3,$4,$5,null,'clock_out','2026-10-24 17:00Z','2026-10-24',$1,null,null)",[id(10),id(11),id(1),id(3),id(4)]);
 const read=()=>q('select public.read_pending_checkout_report_registration() v');
 assert.deepEqual((await read()).items,[],'OFF does not lock historical users');assert.equal((await read()).enforcement_enabled,false);
 await db.query('update checkout_report_registration_private.rollout set enabled=true');
 assert.equal((await read()).items[0].registration_state,'report_missing');
 await db.query("insert into daily_reports(id,company_id,site_id,report_date,status,updated_at,work_description) values($1,$2,$3,'2026-10-24','draft',now(),'synthetic work')",[id(20),id(1),id(4)]);
 await db.query('insert into daily_report_workers(report_id,worker_id) values($1,$2)',[id(20),id(3)]);
 await db.query('update attendance_verifications set daily_report_id=$1',[id(20)]);
 assert.equal((await read()).items[0].registration_state,'reporter_signature_missing');
 await db.query('alter function private.guard_linked_vehicle_meter_report() rename to fixture_temporarily_missing_guard');
 assert.equal((await read()).items[0].registration_state,'report_input_incomplete','Enabled strong framework cannot fall back when guard absent');
 await db.query('alter function private.fixture_temporarily_missing_guard() rename to guard_linked_vehicle_meter_report');
 await db.query('alter table vehicle_meter_events rename to fixture_temporarily_missing_events');
 assert.equal((await read()).items[0].registration_state,'report_input_incomplete','Enabled partial strong framework stays blocked');
 await db.query('alter table fixture_temporarily_missing_events rename to vehicle_meter_events');

 await db.query(`update daily_reports set representative_signer_name='Synthetic reporter',representative_signature_json='{"strokes":[[{}]]}'`);
 let item=(await read()).items[0];assert.equal(item.registration_state,'reporter_saved_waiting_supervisor');assert.equal(item.blocking,false,'Reporter unlock while draft');
 await db.query("update daily_reports set work_description='' ");
 assert.equal((await read()).items[0].registration_state,'report_input_incomplete','Signature cannot bypass required persisted content');
 await db.query("update daily_reports set work_description='synthetic work'");
 await db.query('update daily_report_workers set vehicle_id=$1',[id(40)]);
 assert.equal((await read()).items[0].registration_state,'report_input_incomplete','Vehicle requires odometer');
 await db.query('update daily_report_workers set vehicle_id=null');
 await db.query("insert into vehicle_usage_claims values($1,$2,$3,$4,'2026-10-24',null)",[id(10),id(1),id(3),id(40)]);
 await db.query('update attendance_verifications set vehicle_id=$1',[id(40)]);
 assert.equal((await read()).items[0].registration_state,'report_input_incomplete','Managed claim requires committed meter event');
 await db.query('delete from vehicle_usage_claims');await db.query('update attendance_verifications set vehicle_id=null');
 assert.equal((await read()).items[0].blocking,false);
 const enqueueDefinition=await q("select pg_get_functiondef('private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure) v");
 await db.query("create or replace function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$begin raise exception 'synthetic enqueue failure';end$$");
 let failed=await q('select checkout_report_registration_private.deliver_daily() v');assert.equal(failed.sent,0);assert.equal(failed.failures.length,1);
 assert.equal(await q('select count(*)::int v from checkout_report_registration_private.daily_deliveries'),0,'Failed delivery receipt rolls back');
 await db.query(enqueueDefinition);
 let delivered=await q('select checkout_report_registration_private.deliver_daily() v');assert.equal(delivered.sent,1,JSON.stringify(delivered));
 assert.equal((await q('select public.read_checkout_report_registration_notification($1) v',[id(20)])).items[0].registration_state,'reporter_saved_waiting_supervisor');

 const goodClaims={role:'authenticated',sub:id(2),session_id:id(80),is_anonymous:false};
 const deniedReaders=async()=>{
  await assert.rejects(read,/checkout_report_actor_access_unavailable/);
  await assert.rejects(()=>q('select public.read_checkout_report_registration_notification($1) v',[id(20)]),/checkout_report_actor_access_unavailable/);
 };
 for(const claims of [{...goodClaims,session_id:null},{...goodClaims,session_id:'malformed'},
  {...goodClaims,session_id:id(89)},{...goodClaims,sub:id(99)},
  {...goodClaims,role:'service_role'},{...goodClaims,is_anonymous:true},{...goodClaims,is_anonymous:'false'}]){
  await db.query('select set_config(\'fixture.claims\',$1,false)',[JSON.stringify(claims)]);await deniedReaders();
 }
 await db.query("select set_config('fixture.claims','',false)");
 await db.query("update auth.sessions set not_after=now()-interval '1 minute' where id=$1",[id(80)]);await deniedReaders();
 await db.query('update auth.sessions set not_after=null,user_id=$1 where id=$2',[id(99),id(80)]);await deniedReaders();
 await db.query('update auth.sessions set user_id=$1 where id=$2',[id(2),id(80)]);
 await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[id(2)]);await deniedReaders();
 await db.query('update auth.users set banned_until=null,is_anonymous=true where id=$1',[id(2)]);await deniedReaders();
 await db.query('update auth.users set is_anonymous=false where id=$1',[id(2)]);
 await db.query('delete from auth.sessions where id=$1',[id(80)]);await deniedReaders();
 await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[id(80),id(2)]);
 await db.query('delete from auth.users where id=$1',[id(2)]);await deniedReaders();
 await db.query('insert into auth.users(id) values($1)',[id(2)]);
 await db.query("select set_config('fixture.account','false',false)");await deniedReaders();
 await db.query("select set_config('fixture.account','true',false)");

 await db.query('update app_notifications set read_at=now()');
 delivered=await q('select checkout_report_registration_private.deliver_daily() v');assert.equal(delivered.sent,0);assert.equal(delivered.deduplicated,1,'Read does not resolve business pending');
 await db.query("update checkout_report_registration_private.daily_deliveries set notification_day=notification_day-1");
 assert.equal((await q('select checkout_report_registration_private.deliver_daily() v')).sent,1,'Next daily interval sends again');
 await db.query(`update daily_reports set supervisor_signer_name='Synthetic supervisor',supervisor_signature_json='{"strokes":[[{}]]}',status='signed',signed_at=now(),signature_json=jsonb_build_object('version',3,'representative',representative_signature_json,'supervisor','{\"strokes\":[[{}]]}'::jsonb)`);
 assert.equal((await read()).items[0].registration_state,'signed_projection_unverified');
 assert.equal((await q('select checkout_report_registration_private.deliver_daily() v')).sent,1,'Different reason after supervisor signs');
 assert.equal(await q("select count(*)::int v from app_notifications where body like '現場責任者サイン済み%'"),1);
 await db.query("insert into attendance_entries values($1,$2,$3,$4,'2026-10-24',$5,null,1,0,0,0,'day')",[id(30),id(20),id(1),id(3),id(4)]);
 await db.query(`insert into payroll_statements(company_id,worker_id,period_start,period_end,automatic_calculation,workflow_state,updated_at,detail) values($1,$2,'2026-10-01','2026-10-31',true,'draft',now(),'{"出勤日数":1,"残業時間":0,"早出時間":0,"夜間時間":0}')`,[id(1),id(3)]);
 assert.equal((await q('select public.read_checkout_report_registration_notification($1) v',[id(20)])).resolved,true);
 assert.deepEqual((await read()).items,[],'Source-bound attendance and current normal detail projection stop pending');
 assert.equal((await q('select checkout_report_registration_private.deliver_daily() v')).sent,0);
 await db.query('update payroll_statements set calculation_blocked=true');
 assert.equal((await read()).items[0].registration_state,'signed_projection_unverified','Blocked calculations are not certified');
 await db.query('update payroll_statements set calculation_blocked=false');
 await db.query("update payroll_statements set workflow_state='finalized'");
 assert.equal((await read()).items[0].registration_state,'signed_projection_unverified','Protected payroll not falsely certified');
 await db.query("update payroll_statements set workflow_state='draft'");
 await db.query("insert into attendance_verifications select $1,company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at,work_date,source_clock_in_id,daily_report_id,vehicle_id from attendance_verifications where event_type='clock_out'",[id(12)]);
 assert.ok((await read()).items.every(x=>x.registration_state==='source_conflict'&&x.blocking),'Duplicate outs cannot unlock');
 await db.query('delete from attendance_verifications where id=$1',[id(12)]);
 assert.equal((await q('select checkout_report_registration_private.run_daily_step() v')).complete,true);
 assert.equal((await q('select checkout_report_registration_private.run_daily_step() v')).sent,0,'Rescans dedupe and permit newly registered reports later today');
 assert.equal(await q("select has_function_privilege('authenticated','checkout_report_registration_private.deliver_daily(uuid,integer)','EXECUTE') v"),false,'No client scheduler');
 assert.equal(await q("select has_function_privilege('authenticated','checkout_report_registration_private.read_for_actor(uuid)','EXECUTE') v"),false,'No client arbitrary actor read');

 // Choice module runs against the actual registration reader and current actor
 // helper above, not a replacement authorization implementation.
 await db.query('revoke execute on function checkout_report_registration_private.read_for_actor(uuid) from service_role'); // Fixture default grants differ from captured deployed postgres-only ACL.
 const choiceSql=await readFile('docs/review/checkout-report-choice-candidate/install-off.sql.review-only','utf8');
 const beforeDefinition=await q("select pg_get_functiondef('checkout_report_registration_private.read_for_actor(uuid)'::regprocedure) v");
 const beforeAcl=await q("select proacl::text v from pg_proc where oid='checkout_report_registration_private.read_for_actor(uuid)'::regprocedure");
 await db.query(choiceSql);
 assert.equal(await q("select has_function_privilege('anon','public.choose_checkout_report_registration(uuid,text,boolean)','EXECUTE') v"),false);
 assert.equal(await q("select has_function_privilege('service_role','public.choose_checkout_report_registration(uuid,text,boolean)','EXECUTE') v"),false);
 assert.equal(await q("select has_table_privilege('authenticated','checkout_report_choice_private.choices','INSERT') v"),false);
 await db.query(await readFile('docs/review/checkout-report-choice-candidate/restore-unused-off.sql.review-only','utf8'));
 assert.equal(await q("select pg_get_functiondef('checkout_report_registration_private.read_for_actor(uuid)'::regprocedure) v"),beforeDefinition);
 assert.equal(await q("select proacl::text v from pg_proc where oid='checkout_report_registration_private.read_for_actor(uuid)'::regprocedure"),beforeAcl);
 await db.query(choiceSql);
 await db.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-25 08:00Z','2026-10-25',null,null,null),($2,$3,$4,$5,null,'clock_out','2026-10-25 17:00Z','2026-10-25',$1,null,null)",[id(50),id(51),id(1),id(3),id(4)]);
 const target=async()=> (await read()).items.find(x=>x.source_clock_in_id===id(50));
 assert.equal((await target()).choice_available,undefined,'OFF keeps existing contract');
 await db.query('insert into checkout_report_choice_private.rollout values($1,true)',[id(1)]);
 assert.equal((await target()).registration_state,'report_missing','Single member goes directly to report');
 await db.query('insert into workers(id,company_id,user_id) values($1,$2,$3)',[id(6),id(1),id(99)]);
 await db.query('insert into company_members values($1,$2)',[id(1),id(99)]);
 await db.query("insert into attendance_verifications values($1,$2,$3,$4,null,'clock_in','2026-10-25 09:00Z','2026-10-25',null,null,null)",[id(52),id(1),id(6),id(4)]);
 assert.equal((await target()).registration_state,'report_choice_required');assert.equal((await target()).member_count,2);
 const choose=async(create,scope)=> q('select public.choose_checkout_report_registration($1,$2,$3) v',[id(50),scope??(await target()).scope_fingerprint,create]);
 await assert.rejects(()=>choose(false,'wrong'),/choice_stale/);
 await db.query("insert into attendance_verifications values($1,$3,$4,$5,null,'clock_in','2026-10-26 08:00Z','2026-10-26',null,null,null),($2,$3,$4,$5,null,'clock_out','2026-10-26 17:00Z','2026-10-26',$1,null,null)",[id(70),id(71),id(1),id(3),id(4)]);
 const single=async()=> (await read()).items.find(x=>x.source_clock_in_id===id(70));
 assert.equal((await single()).member_count,1);
 await q('select public.choose_checkout_report_registration($1,$2,true) v',[id(70),(await single()).scope_fingerprint]);
 await db.query("insert into attendance_verifications values($1,$2,$3,$4,null,'clock_in','2026-10-26 09:00Z','2026-10-26',null,null,null)",[id(72),id(1),id(6),id(4)]);
 assert.equal((await single()).member_count,2);assert.equal((await single()).registration_state,'report_missing');
 await assert.rejects(()=>q('select public.choose_checkout_report_registration($1,$2,false) v',[id(70),'unused']),/choice_stale/);
 await assert.rejects(async()=>q('select public.choose_checkout_report_registration($1,$2,false) v',[id(70),(await single()).scope_fingerprint]),/already_started/);
 await choose(false);assert.equal((await target()).registration_state,'checkout_deferred');assert.equal((await target()).blocking,false);
 await choose(false);assert.equal(await q('select count(*)::int v from checkout_report_choice_private.choices'),2,'Retry is idempotent');
 // Fresh authoritative read after reconnect has the same persisted choice.
 assert.equal((await target()).registration_state,'checkout_deferred');
 await choose(true);assert.equal((await target()).report_started,true);assert.equal((await target()).registration_state,'report_missing');assert.equal((await target()).blocking,true);
 await assert.rejects(()=>choose(false),/already_started/);
 const history=await q('select (deferred_at is not null and started_at is not null) v from checkout_report_choice_private.choices');assert.equal(history,true,'Later explicit create retains checkout-only history');
 await db.query("insert into daily_reports(id,company_id,site_id,report_date,status,updated_at,work_description,representative_signer_name,representative_signature_json) values($1,$2,$3,'2026-10-25','draft',now(),'synthetic work','Synthetic reporter','{\"strokes\":[[{}]]}')",[id(60),id(1),id(4)]);
 await db.query('insert into daily_report_workers(report_id,worker_id) values($1,$2)',[id(60),id(3)]);
 await db.query('update attendance_verifications set daily_report_id=$1 where id=any($2::uuid[])',[id(60),[id(50),id(51)]]);
 assert.equal((await target()).blocking,false,'Only persisted content/reporter signature release started flow');
 assert.equal((await target()).registration_state,'reporter_saved_waiting_supervisor');
 const restoreSql=await readFile('docs/review/checkout-report-choice-candidate/restore-unused-off.sql.review-only','utf8'); await assert.rejects(()=>db.query(restoreSql),/already used/);await db.query('rollback');
 await db.query('select set_config(\'fixture.actor\',$1,false)',[id(99)]);await db.query('select set_config(\'fixture.session\',$1,false)',[id(81)]);
 await assert.rejects(()=>q('select public.choose_checkout_report_registration($1,$2,true) v',[id(50),'wrong']),/choice_stale/);
 await db.query('select set_config(\'fixture.actor\',$1,false)',[id(2)]);await db.query('select set_config(\'fixture.session\',$1,false)',[id(80)]);
 console.log('PASS actual registration choice OFF/single/multiple/defer/restart/explicit-later-create/retry/started-cannot-defer/reporter-release/source-actor/unused-restore');
 await db.query('select set_config(\'fixture.actor\',$1,false)',[id(99)]);
 await db.query('select set_config(\'fixture.session\',$1,false)',[id(81)]);
 assert.deepEqual((await read()).items,[],'Other actor gets no source');
 await assert.rejects(()=>q('select public.read_checkout_report_registration_notification($1) v',[id(20)]),/notification_target_unavailable/);
 assert.equal(await q("select has_function_privilege('authenticated','checkout_report_registration_private.current_actor()','EXECUTE') v"),false,'No direct actor helper access');
 console.log('PASS synthetic actor isolation/OFF/source input/meter/reporter unlock/daily dedup/failure rollback/reason transition/projection stop/private grants/scheduler');
} finally {await db.end();}
