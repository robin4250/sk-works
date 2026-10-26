// CI PostgreSQL17 only. Reuse source-bound installers and actual financial
// producers; do not replay the previous 247-case report suite.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url));
const ordinary=resolve(here,'../explicit-finalization-candidate');
const folder=await mkdtemp(join(tmpdir(),'attendance-entry-access-'));
try {
 const emitted=join(folder,'ordinary.mjs');
 const result=spawnSync(process.execPath,[ordinary+'/verify_ordinary_explicit_finalization.mjs'],{
  stdio:'inherit',env:{...process.env,SKO_ORDINARY_EXPLICIT_EMIT_ONLY:emitted}});
 assert.equal(result.status,0);
 const source=await readFile(emitted,'utf8');
 const cut=" phase='ordinary-default-off-install';";
 assert.equal(source.split(cut).length,2);
 const prerequisites=source.slice(source.indexOf(" phase='ordinary-highest-management-real-03-04-05-install';"),source.indexOf(' const managementUser=id(9850)'));
 const prefix=source.slice(0,source.indexOf(cut));
 const tail=source.slice(source.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='entry-session-new-module';
 const entryRoot=process.env.SKO_ENTRY_ACCESS_ROOT;
 const installSql=await readFile(entryRoot+'/install-off.sql.review-only','utf8');
 const restoreSql=await readFile(entryRoot+'/restore-unused.sql.review-only','utf8');
 const oldSignatures=['public.force_manage_attendance(text,jsonb)','public.force_manage_attendance_with_proof(text,jsonb,text)'];
 const oldCatalog=()=>q("select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p where p.oid=any(select to_regprocedure(x)::oid from unnest($1::text[]) x)",[oldSignatures]);
 const catalogBefore=await oldCatalog(),businessBefore=await business();
 if(process.env.SKO_ENTRY_COLLECTOR_PAIR==='1'){
  await exec(await readFile(entryRoot+'/../collector-current-core-20261026/install-off.sql.review-only','utf8'));
  eq(await q("select private.reauthentication_scope('master.security_collector.read') v"),'master_security','Paired collector extends only the existing Master scope');
  eq(await q("select count(*)::int v from private.reauthentication_rollout"),4,'Paired collector preserves all four rollout scopes');
  eq(await oldCatalog(),catalogBefore,'Paired collector preserves attendance writer sources/OIDs/ACL');
  eq(await business(),businessBefore,'Paired collector OFF install preserves business and finance');
 }
 await exec(installSql);
 eq(await business(),businessBefore,'Entry OFF install changes no business/financial/signature rows');
 eq(await q('select count(*)::int v from attendance_entry_access_private.rollout'),0,'New entry gate absent/default OFF');
 const installedCatalog=await oldCatalog();
 await exec('alter table attendance_entry_access_private.grants disable row level security');
 await reject(()=>exec(restoreSql),/attendance_entry_restore_catalogue_changed/);await exec('rollback');
 eq(await oldCatalog(),installedCatalog,'Changed new-table security metadata refuses restoration before original writers change');
 await exec('alter table attendance_entry_access_private.grants enable row level security');
 await exec('create view public.fixture_unknown_entry_dependency as select attendance_entry_access_private.required() required');
 await reject(()=>exec(restoreSql),/depend|cannot drop/i);await exec('rollback');
 eq(await oldCatalog(),installedCatalog,'Unknown dependency rolls back entire unused restore');
 eq(await q("select to_regclass('public.fixture_unknown_entry_dependency') is not null v"),true,'Unknown external view remains intact');
 await exec('drop view public.fixture_unknown_entry_dependency');
 await exec(restoreSql);
 eq(await oldCatalog(),catalogBefore,'Unused restore exact full pg_proc including source/OID/ACL/owner/config');
 eq(await business(),businessBefore,'Unused restoration preserves all business rows');
 await exec(installSql);
 eq(await oldCatalog(),installedCatalog,'Reinstall retains both original public OIDs and installed bodies');
 const manager=id(9850),managerSid=id(9851),secondSid=id(9852);
 await client.query('insert into auth.users(id) values($1)',[manager]);
 await client.query('insert into auth.sessions(id,user_id) values($1,$2),($3,$2)',[managerSid,manager,secondSid]);
 await client.query("insert into company_members(company_id,user_id,role) values($1,$2,'owner')",[A,manager]);
 await exec("select set_config('fixture.manager','on',false)");
 await sharedCall(manager,managerSid,"select public.set_secondary_password('synthetic-entry-known') v");
 await client.query('insert into attendance_admin_override_private.rollout values($1,true)',[A]);
 await client.query('insert into management_registered_allowance_private.rollout values($1,true)',[A]);
 const capabilities=()=>sharedCall(manager,managerSid,'select public.attendance_management_entry_capabilities() v');
 eq((await capabilities()).enabled,false,'OFF client keeps existing page behavior');
 const open=(password='synthetic-entry-known',actor=manager,sid=managerSid,cid=A)=>sharedCall(actor,sid,'select public.open_attendance_management_access($1,$2) v',[password,cid]);
 await reject(()=>open(),/attendance_entry_disabled/);
 await client.query('insert into attendance_entry_access_private.rollout(company_id,enabled) values($1,true)',[A]);
 eq((await capabilities()).enabled,true,'Explicit company fixture activation only');
 eq(await q('select count(*)::int v from private.reauthentication_rollout where enabled'),0,'No old global per-operation password gates enabled');
 const credential=()=>q('select to_jsonb(c) v from public.user_secondary_credentials c where user_id=$1',[manager]);
 for(let i=1;i<=5;i++){
  const wrong=await open('synthetic-wrong');eq(wrong.ok,false,'Wrong entry PW returns structured failure');
  eq(await q('select failed_attempts v from public.user_secondary_credentials where user_id=$1',[manager]),i,'Wrong password counter commits instead of transaction rollback');
 }
 await reject(()=>open(),/temporarily locked/);
 eq(await q('select count(*)::int v from attendance_entry_access_private.grants'),0,'Failed entry creates no grant');
 await client.query('update public.user_secondary_credentials set locked_until=null,failed_attempts=0 where user_id=$1',[manager]);
 let access=await open();eq(access.ok,true,'One real password verification opens one entry grant');assert.match(access.grant,/^[a-f0-9]{64}$/);
 eq(await q('select token_hash=$1 v from attendance_entry_access_private.grants',[access.grant]),false,'Database never stores raw grant');
 phase='entry-authorized-actual-crud';
 const afterEntryCredential=await credential();
 const cell=(day='2026-10-20',extra={})=>({worker_id:W,date:day,mode:'work',site_id:SITE,man_days:1,overtime_hours:0,early_hours:0,night_hours:0,allowance_names:[],company_allowance_selections:choices([]),company_allowance_legacy_labels:'',work_description:'入口認証後の正規管理操作',clock_in:'08:00',clock_out:'17:00',...extra});
 const deleteCell=day=>{const x=cell(day,{mode:'off'});delete x.company_allowance_selections;delete x.company_allowance_legacy_labels;return x;};
 const perform=(action,items,grant=access.grant,actor=manager,sid=managerSid,cid=A)=>sharedCall(actor,sid,'select public.force_manage_attendance_with_access($1,$2::jsonb,$3,$4) v',[action,JSON.stringify(items),grant,cid]);
 const salaryDays=()=>q("select coalesce((select (detail->>'出勤日数')::numeric from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'),0) v",[A,W]);
 const invoiceAmount=()=>q('select coalesce((select grand_total from invoices where company_id=$1 and customer_id=$2 and automatic_calculation),0) v',[A,customer]);
 const salaryBefore=Number(await salaryDays()??0),invoiceBefore=Number(await invoiceAmount()??0);
 await reject(()=>sharedCall(manager,managerSid,'select public.force_manage_attendance($1,$2::jsonb) v',['upsert',JSON.stringify([cell()])]),/attendance_entry_access_required/);
 await reject(()=>sharedCall(manager,managerSid,'select public.force_manage_attendance_with_proof($1,$2::jsonb,$3) v',['upsert',JSON.stringify([cell()]),'a'.repeat(64)]),/attendance_entry_access_required/);
 eq(await perform('upsert',[cell()]),1,'First save uses page grant without another password');
 eq(Number(await salaryDays()),salaryBefore+1,'Actual payroll adds exactly one entry day');
 eq(Number(await invoiceAmount()),invoiceBefore+10000,'Actual invoice adds one actual participant-day');
 eq(await perform('upsert',[cell('2026-10-20',{work_description:'同じ画面で正規編集'})]),1,'Edit reuses same page authorization without another password');
 eq(Number(await salaryDays()),salaryBefore+1,'Edit does not duplicate salary day');
 eq(Number(await invoiceAmount()),invoiceBefore+10000,'Edit does not duplicate invoice amount');
 eq(await perform('delete',[deleteCell('2026-10-20')]),1,'Delete uses same page authorization without another password');
 eq(Number(await salaryDays()),salaryBefore,'Actual payroll removes selected day');
 eq(Number(await invoiceAmount()),invoiceBefore,'Actual invoice removes selected participant-day');
 eq(await q("select count(*)::int v from payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-10-01'",[A,W]),0,'Actual producer removes empty daily-pay draft rather than fabricating zero-day statement');
 eq(await q('select count(*)::int v from invoices where company_id=$1 and customer_id=$2 and automatic_calculation',[A,customer]),0,'Actual producer removes empty automatic invoice draft');
 eq(await credential(),afterEntryCredential,'Multiple CRUD operations never call password verifier again');
 eq(await q("select count(*)::int v from attendance_entry_access_private.events where event='management'"),3,'Each actual management write remains audited');
 phase='entry-denials-and-lifecycle';
 const safeBusiness=await business();
 await reject(()=>perform('upsert',[cell()],access.grant,manager,secondSid),/attendance_entry_access_required/);
 await reject(()=>perform('upsert',[cell()],access.grant,memberB,sidB),/attendance_admin_current_management_required|attendance_entry_access_required/);
 await reject(()=>perform('upsert',[cell()],access.grant,manager,managerSid,B),/attendance_entry_access_required/);
 eq(await business(),safeBusiness,'Other SID/actor/company cannot modify business rows with copied token');
 await exec("select set_config('fixture.manager','off',false)");await reject(()=>perform('upsert',[cell()]),/attendance_admin_current_management_required/);await exec("select set_config('fixture.manager','on',false)");
 await client.query("update company_members set role='worker' where user_id=$1",[manager]);await reject(()=>perform('upsert',[cell()]),/attendance_admin_current_management_required/);await client.query("update company_members set role='owner' where user_id=$1",[manager]);
 const beforeBadBatch=await business();
 await reject(()=>perform('upsert',[cell('2026-10-19'),cell('2026-10-18',{clock_in:'invalid-time'})]),/time zone|invalid input/i);
 eq(await business(),beforeBadBatch,'Failed actual batch rolls back original payroll/invoice/source/audit changes');
 eq(await credential(),afterEntryCredential,'Failed batch still performs no password verification');
 await sharedCall(manager,managerSid,'select public.close_attendance_management_access($1) v',[access.grant]);
 await reject(()=>perform('upsert',[cell()]),/attendance_entry_access_required/);
 access=await open();
 await client.query("update attendance_entry_access_private.grants set created_at=statement_timestamp()-interval '16 minutes',expires_at=statement_timestamp()-interval '1 minute' where token_hash=encode(extensions.digest($1,'sha256'),'hex')",[access.grant]);
 await reject(()=>perform('upsert',[cell()]),/attendance_entry_access_required/);
 access=await open();
 await sharedCall(manager,managerSid,"select public.set_secondary_password('synthetic-entry-rotated') v");
 await reject(()=>perform('upsert',[cell()]),/attendance_entry_access_required/);
 access=await open('synthetic-entry-rotated');
 const revision=await q('select revision::text v from attendance_entry_access_private.rollout where company_id=$1',[A]);
 eq(String(await sharedCall(manager,managerSid,'select public.revoke_company_attendance_access($1,$2,$3,$4) v',[access.grant,A,revision,'合成の復旧試験による明示失効'])),String(Number(revision)+1),'Authorized audited revision change invalidates previous grants');
 await reject(()=>perform('upsert',[cell()]),/attendance_entry_access_required/);
 access=await open('synthetic-entry-rotated');
 eq(await perform('upsert',[cell('2026-10-18')]),1,'Real re-entry recovers after explicit revision revocation');
 const beforeToggle=access.grant;
 await client.query('update attendance_entry_access_private.rollout set enabled=false where company_id=$1',[A]);
 await reject(()=>perform('upsert',[cell()]),/attendance_entry_access_required/);
 await client.query('update attendance_entry_access_private.rollout set enabled=true where company_id=$1',[A]);
 await reject(()=>perform('upsert',[cell()],beforeToggle),/attendance_entry_access_required/);
 access=await open('synthetic-entry-rotated');
 await client.query('delete from auth.sessions where id=$1',[managerSid]);
 await reject(()=>perform('upsert',[cell()]),/reauthentication_required/);
 await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[managerSid,manager]);
 phase='entry-direct-privilege-and-used-restore';
 for(const role of ['anon','service_role']){
  await exec('set role '+role);try{await reject(()=>q('select public.open_attendance_management_access($1,$2) v',['synthetic-entry-rotated',A]),{code:'42501'});await reject(()=>q('select public.force_manage_attendance_with_access($1,$2::jsonb,$3,$4) v',['upsert',JSON.stringify([cell()]),access.grant,A]),{code:'42501'});}finally{await exec('reset role');}
 }
 await exec('set role authenticated');try{
  await reject(()=>q('select * from attendance_entry_access_private.grants'),{code:'42501'});
  await reject(()=>q('select attendance_entry_access_private.require_access($1,$2) v',[access.grant,A]),{code:'42501'});
 }finally{await exec('reset role');}
 await client.query('update attendance_entry_access_private.rollout set enabled=false where company_id=$1',[A]);
 await reject(()=>exec(restoreSql),/attendance_entry_restore_used_or_configured/);await exec('rollback');
 eq(await q('select count(*)::int v from attendance_entry_access_private.events')>0,true,'Used restoration keeps every authorization/audit record');
 phase='entry-bounded-retention';
 await client.query('update attendance_entry_access_private.rollout set enabled=true where company_id=$1',[A]);
 access=await open('synthetic-entry-rotated');
 const activeBefore=await q("select to_jsonb(g) v from attendance_entry_access_private.grants g where token_hash=encode(extensions.digest($1,'sha256'),'hex')",[access.grant]);
 const currentRevision=await q('select revision v from attendance_entry_access_private.rollout where company_id=$1',[A]);
 await client.query("insert into attendance_entry_access_private.grants(token_hash,actor_id,session_id,company_id,revision,credential_fingerprint,created_at,expires_at) select encode(extensions.digest('retention-old-grant-'||n,'sha256'),'hex'),$1,$2,$3,$4,'synthetic-fingerprint',statement_timestamp()-interval '3 days',statement_timestamp()-interval '3 days'+interval '15 minutes' from generate_series(1,1105)n",[manager,managerSid,A,currentRevision]);
 await client.query("insert into attendance_entry_access_private.events(event,actor_id,session_id,company_id,revision,created_at) select 'closed',$1,$2,$3,$4,clock_timestamp()-interval '91 days' from generate_series(1,1105)n",[manager,managerSid,A,currentRevision]);
 const retainedEvents=()=>q("select jsonb_agg(to_jsonb(e) order by id) v from attendance_entry_access_private.events e where created_at>=clock_timestamp()-interval '90 days'");
 const retainedGrants=()=>q("select jsonb_agg(to_jsonb(g) order by id) v from attendance_entry_access_private.grants g where not(expires_at<clock_timestamp() and coalesce(revoked_at,expires_at)<clock_timestamp()-interval '1 day')");
 const grantsBefore=await retainedGrants(),logsBefore=await retainedEvents(),purgeBusinessBefore=await business();
 const firstPurge=await q('select attendance_entry_access_private.purge_retained(1000) v');
 eq(firstPurge.grants_deleted,1000,'First retention call deletes exactly 1000 expired grant hashes');
 eq(firstPurge.events_deleted,0,'First call cannot exceed total batch budget across tables');
 const secondPurge=await q('select attendance_entry_access_private.purge_retained(1000) v');
 eq(secondPurge.grants_deleted,105,'Second retention call removes only remaining eligible grants');
 eq(secondPurge.events_deleted,895,'Second call uses only remaining shared event budget');
 const thirdPurge=await q('select attendance_entry_access_private.purge_retained(1000) v');
 eq(thirdPurge.grants_deleted,0,'No extra expired grant rows are invented');
 eq(thirdPurge.events_deleted,210,'Third call completes the old event backlog');
 eq(await retainedEvents(),logsBefore,'Every newer authorization event remains byte-identical');
 eq(await retainedGrants(),grantsBefore,'Every live or recently expired/revoked grant remains byte-identical');
 eq(await q("select to_jsonb(g) v from attendance_entry_access_private.grants g where id=$1",[activeBefore.id]),activeBefore,'Current active grant remains byte-identical');
 eq(await q("select count(*)::int v from attendance_entry_access_private.grants where expires_at<clock_timestamp() and coalesce(revoked_at,expires_at)<clock_timestamp()-interval '1 day'"),0,'Eligible grant backlog is empty after bounded calls');
 eq(await q("select count(*)::int v from attendance_entry_access_private.events where created_at<clock_timestamp()-interval '90 days'"),0,'Eligible event backlog is empty after bounded calls');
 const retention=await q('select to_jsonb(s) v from attendance_entry_access_private.retention_state s');
 eq(String(retention.runs),'3','Bounded one-row summary records every maintenance call');
 eq(String(retention.grants_deleted),'1105','Summary retains cumulative grant deletion count');
 eq(String(retention.events_deleted),'1105','Summary retains cumulative event deletion count');
 eq(retention.last_grants,0,'Summary retains last grant batch count');eq(retention.last_events,210,'Summary retains last event batch count');
 eq(await q('select count(*)::int v from attendance_entry_access_private.retention_state'),1,'Maintenance audit itself stays one bounded row');
 eq(await business(),purgeBusinessBefore,'Retention cannot mutate original business, salary, invoice or signing rows');
 for(const limit of [null,0,1001])await reject(()=>q('select attendance_entry_access_private.purge_retained($1) v',[limit]),/attendance_entry_retention_limit/);
 eq(await q('select to_jsonb(s) v from attendance_entry_access_private.retention_state s'),retention,'Invalid limits cannot record a false maintenance run');
 for(const role of ['anon','authenticated','service_role']){
  await exec('set role '+role);try{await reject(()=>q('select attendance_entry_access_private.purge_retained(1000) v'),{code:'42501'});}finally{await exec('reset role');}
 }
 eq(await perform('upsert',[cell('2026-10-17')]),1,'An unchanged current grant still authorizes real management after maintenance');
 await client.query('update attendance_entry_access_private.rollout set enabled=false where company_id=$1',[A]);
 await reject(()=>exec(restoreSql),/attendance_entry_restore_retention_used/);await exec('rollback');
 eq(await q('select to_jsonb(s) v from attendance_entry_access_private.retention_state s'),retention,'Purge never turns a used module back into an unused uninstall candidate');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,actual_four_financial_producers:true,one_entry_password_multiple_crud:true,wrong_password_counter_commits:true,session_company_role_credential_revision_bound:true,no_global_per_operation_activation:true,unused_restore_exact:true,unknown_dependency_refused:true,used_restore_refused:true,bounded_owner_retention:true,current_grants_and_recent_logs_preserved:true,production_changed:false}));
`;
 const script=join(folder,'proof.mjs');await writeFile(script,prefix+prerequisites+unit+tail);
 const run=spawnSync(process.execPath,[script,process.argv[2]],{stdio:'inherit',env:{...process.env,
  SKO_ORDINARY_EXPLICIT_ROOT:ordinary,SKO_ENTRY_ACCESS_ROOT:here,
  SKO_DOCUMENT_CANDIDATE:resolve(here,'../supervisor-document-candidate/document-signature-and-edit.sql.review-only'),
  SKO_DOCUMENT_TRIGGER_PINS:resolve(here,'../supervisor-document-candidate/trigger-source-pins.json'),
  SKO_ADMIN_CANDIDATE:resolve(here,'../attendance-admin-override-candidate/attendance-admin-override.sql.review-only'),
  SKO_ADMIN_ORIGINALS:resolve(here,'../attendance-admin-override-candidate/native-original-sources.sql')}});
 if(run.error)throw run.error;process.exitCode=run.status??1;
}finally{await rm(folder,{recursive:true,force:true});}

