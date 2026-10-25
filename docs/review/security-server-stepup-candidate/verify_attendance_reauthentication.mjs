// PG17 only. Reuse exact installers, never replay prior broad functional suites.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';import {spawnSync} from 'node:child_process';
const here=fileURLToPath(new URL('.',import.meta.url));
const management=resolve(here,'../management-registered-allowances-candidate');
const folder=await mkdtemp(join(tmpdir(),'attendance-stepup-native-'));
try {
 const emitted=join(folder,'management.mjs');
 const result=spawnSync(process.execPath,[resolve(management,'verify_management_registered_allowances.mjs')],{stdio:'inherit',env:{...process.env,SKO_MANAGEMENT_REGISTERED_EMIT_ONLY:emitted}});assert.equal(result.status,0);
 const source=await readFile(emitted,'utf8'),marker=" eq(await q('select count(*)::int v from management_registered_allowance_private.rollout'),0,";
 assert.equal(source.split(marker).length,2);const prefix=source.slice(0,source.indexOf(marker)),tail=source.slice(source.indexOf('}catch(error){'));
 const unit=String.raw`
 phase='stepup-proof-prerequisites';
 await exec('create schema extensions;create extension pgcrypto with schema extensions;alter table auth.users add column encrypted_password text');
 await exec("create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',coalesce(nullif(current_setting('fixture.role',true),''),'authenticated'),'sub',current_setting('fixture.actor',true),'session_id',coalesce(nullif(current_setting('fixture.sid',true),''),'00000000-0000-0000-0000-000000000080'),'is_anonymous',false)$$;");
 await exec("create table private.account_deletion_access_restrictions(user_id uuid primary key);create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;create table private.master_admins(user_id uuid primary key,enabled boolean);create function public.is_current_user_master_admin() returns boolean language sql security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);alter table public.user_secondary_credentials enable row level security;revoke all on public.user_secondary_credentials from public,anon,authenticated;create table private.master_feature_settings(feature_key text primary key,enabled boolean,updated_at timestamptz,updated_by uuid);create function public.current_master_feature_flags() returns jsonb language sql as $$select '{}'::jsonb$$;");
 await exec(await readFile('supabase/tests/fixtures/secondary_reset_before.sql','utf8'));
 await exec(await readFile('supabase/tests/fixtures/reauthentication_master_before.sql','utf8'));
 await exec(await readFile('tool/staged/reauthentication_proofs.sql','utf8'));
 await exec(await readFile('docs/review/security-server-stepup-candidate/verify_secondary_password.source.sql','utf8'));
 await exec('revoke all on function public.verify_secondary_password(text) from public,anon;grant execute on function public.verify_secondary_password(text) to authenticated');
 const forceOid=await q("select 'public.force_manage_attendance(text,jsonb)'::regprocedure::oid v");
 const definition=await q("select pg_get_functiondef('public.force_manage_attendance(text,jsonb)'::regprocedure) v");
 const acl=await q("select proacl::text v from pg_proc where oid='public.force_manage_attendance(text,jsonb)'::regprocedure");
 await exec(await readFile('tool/staged/attendance_reauthentication.sql','utf8'));
 eq(await q("select enabled v from private.reauthentication_rollout where scope='attendance_management'"),false,'Default OFF');
 eq(await q("select 'public.force_manage_attendance(text,jsonb)'::regprocedure::oid v"),forceOid,'Old public OID retained');
 await exec(await readFile('tool/staged/attendance_reauthentication_restore_unused.sql','utf8'));
 eq(await q("select pg_get_functiondef('public.force_manage_attendance(text,jsonb)'::regprocedure) v"),definition,'Unused restore exact function');
 eq(await q("select proacl::text v from pg_proc where oid='public.force_manage_attendance(text,jsonb)'::regprocedure"),acl,'Unused restore exact ACL');
 await exec(await readFile('tool/staged/attendance_reauthentication.sql','utf8'));
 await exec("select set_config('fixture.manager','on',false)");
 await client.query('insert into attendance_admin_override_private.rollout values($1,true)',[A]);
 const cell=(worker=W,day='2026-10-29',more={})=>({worker_id:worker,date:day,mode:'work',site_id:SITE,man_days:1,overtime_hours:0,early_hours:0,night_hours:0,allowance_names:[],work_description:'本人確認付き管理入力',clock_in:'08:00',clock_out:'17:00',...more});
 const old=(action,items)=>sharedCall(U,id(80),'select public.force_manage_attendance($1,$2::jsonb) v',[action,JSON.stringify(items)]);
 const getTarget=(action,items,actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.attendance_management_reauthentication_target($1,$2::jsonb) v',[action,JSON.stringify(items)]);
 const perform=(action,items,proof,actor=U,sid=id(80))=>sharedCall(actor,sid,'select public.force_manage_attendance_with_proof($1,$2::jsonb,$3) v',[action,JSON.stringify(items),proof]);
 eq(await old('upsert',[cell()]),1,'OFF permits actual old writer');
 await sharedCall(U,id(80),"select public.set_secondary_password('synthetic-known-secondary') v");
 await reject(()=>getTarget('upsert',[cell()]),{code:'42501',message:'attendance_reauthentication_disabled'});
 await client.query("update private.reauthentication_rollout set enabled=true where scope='attendance_management'");
 await reject(()=>old('upsert',[cell()]),{code:'42501',message:'reauthentication_required'});
 await reject(()=>getTarget('upsert',[cell()]),{code:'42501',message:'attendance_reauthentication_recovery_dependency_missing'});
 await client.query("update private.reauthentication_rollout set enabled=true where scope='secondary_password'");
 const verifySecondary=password=>sharedCall(U,id(80),'select public.verify_secondary_password($1) v',[password]);
 for(let i=0;i<5;i++)eq(await verifySecondary('synthetic-wrong'),false,'Direct verifier records failure');
 await reject(()=>verifySecondary('synthetic-known-secondary'),/secondary password temporarily locked/);
 await reject(()=>sharedCall(U,id(80),"select public.set_secondary_password('synthetic-bypass-lock') v"),{code:'42501',message:'reauthentication_required'});
 eq(await q('select failed_attempts v from user_secondary_credentials where user_id=$1',[U]),5,'Blocked setter cannot reset lockout');
 await client.query("update user_secondary_credentials set locked_until=clock_timestamp()-interval '1 second' where user_id=$1",[U]);
 eq(await verifySecondary('synthetic-known-secondary'),true,'Known secondary remains usable after lock expiry');
 eq(await q('select failed_attempts v from user_secondary_credentials where user_id=$1',[U]),0,'Successful verifier resets failures');
 const second=[];
 const connect=async()=>{const c=new pg.Client({connectionString:destination.href});await c.connect();second.push(c);await c.query("set statement_timeout='6s';select set_config('fixture.manager','on',false)");return c;};
 try {
 const issuer=await connect();await issuer.query("select set_config('fixture.role','service_role',false);set role service_role");
 const issue=async target=>{const nonce=createHash('sha256').update(String(Math.random())+Date.now()).digest('hex');await issuer.query('select public.issue_reauthentication_proof($1,$2,$3,$4::jsonb,$5)',[U,id(80),'attendance.manage',JSON.stringify(target),createHash('sha256').update(nonce).digest('hex')]);return nonce;};
 const items=[cell()];const target=await getTarget('upsert',items),proof=await issue(target);
 eq(target.company_id,A,'Actual actor company');eq(target.action,'upsert','Exact action');
 eq(await getTarget('upsert',[Object.fromEntries(Object.entries(items[0]).reverse())]),target,'JSON object order canonicalized by server');
 await reject(()=>perform('delete',items,proof),{code:'42501',message:'reauthentication_required'});
 for(const changed of [cell(W2),cell(W,'2026-10-28'),cell(W,'2026-10-29',{site_id:SITE2}),cell(W,'2026-10-29',{night_hours:1}),cell(W,'2026-10-29',{work_description:'改変'})])await reject(()=>perform('upsert',[changed],proof),{code:'42501',message:'reauthentication_required'});
 await reject(()=>perform('upsert',items,proof,memberB,sidB),{code:'42501',message:'reauthentication_required'});
 await client.query('insert into auth.sessions(id,user_id) values($1,$2)',[id(8090),U]);
 await reject(()=>perform('upsert',items,proof,U,id(8090)),{code:'42501',message:'reauthentication_required'});
 eq(await perform('upsert',items,proof),1,'Actual writer succeeds only with exact proof');
 await reject(()=>perform('upsert',items,proof),{code:'42501',message:'reauthentication_required'});
 const expired=await issue(target);await client.query("update private.reauthentication_proofs set issued_at=clock_timestamp()-interval '3 minutes',expires_at=clock_timestamp()-interval '1 minute' where proof_hash=$1",[createHash('sha256').update(expired).digest('hex')]);await reject(()=>perform('upsert',items,expired),{code:'42501',message:'reauthentication_required'});
 const snapshot=()=>q("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(r) order by id) from daily_reports r),'workers',(select jsonb_agg(to_jsonb(w) order by report_id,worker_id) from daily_report_workers w),'audit',(select jsonb_agg(to_jsonb(o) order by id) from attendance_admin_override_private.operations o)) v");
 const badItems=[cell(W3,'2026-10-27'),cell(W7,'2026-10-26',{clock_in:'not-a-time'})],badProof=await issue(await getTarget('upsert',badItems)),before=await snapshot();
 await reject(()=>perform('upsert',badItems,badProof),/time zone "not-a-time" not recognized/);eq(await snapshot(),before,'Failed actual batch restores all source and audit state');
 eq(await q('select consumed_at is null v from private.reauthentication_proofs where proof_hash=$1',[createHash('sha256').update(badProof).digest('hex')]),true,'Failure rolls back proof consumption');
 await reject(()=>issue({...target,company_id:B}),{code:'42501'});
 await exec("select set_config('fixture.manager','off',false)");await reject(()=>getTarget('upsert',items),{code:'42501'});await exec("select set_config('fixture.manager','on',false)");
 await client.query('insert into company_members(company_id,user_id,role) values($1,$2,$3)',[B,U,'owner']);await reject(()=>getTarget('upsert',items),{code:'42501',message:'attendance_reauthentication_single_company_required'});await client.query('delete from company_members where company_id=$1 and user_id=$2',[B,U]);
 for(const role of ['anon','service_role']){
  await exec('set role '+role);try{await reject(()=>q('select public.force_manage_attendance_with_proof($1,$2::jsonb,$3) v',['upsert',JSON.stringify(items),proof]),{code:'42501'});await reject(()=>q('select public.attendance_management_reauthentication_target($1,$2::jsonb) v',['upsert',JSON.stringify(items)]),{code:'42501'});if(role==='service_role')await reject(()=>q('select public.force_manage_attendance($1,$2::jsonb) v',['upsert',JSON.stringify(items)]),{code:'42501',message:'reauthentication_required'});}finally{await exec('reset role');}
 }
 await exec('set role authenticated');try{await reject(()=>q('select attendance_stepup_private.force_manage_attendance_unproven($1,$2::jsonb) v',['upsert',JSON.stringify(items)]),{code:'42501'});}finally{await exec('reset role');}
 // Prove old OID dependencies reach the gate, not a moved unproven writer.
 await exec("create function public.fixture_dependent_old_call(text,jsonb) returns integer language sql as $$select public.force_manage_attendance($1,$2)$$;grant execute on function public.fixture_dependent_old_call(text,jsonb) to authenticated");
 await reject(()=>sharedCall(U,id(80),'select public.fixture_dependent_old_call($1,$2::jsonb) v',['upsert',JSON.stringify(items)]),{code:'42501',message:'reauthentication_required'});
 // Actual SHARE lock: two management callers coexist, membership writes wait.
 const concurrentA=await connect(),concurrentB=await connect(),membership=await connect();
 for(const c of [concurrentA,concurrentB])await c.query("select set_config('fixture.actor',$1,false),set_config('fixture.sid',$2,false);",[U,id(80)]);
 await concurrentA.query('begin');await concurrentA.query('set role authenticated');await concurrentA.query('select public.attendance_management_reauthentication_target($1,$2::jsonb)',['upsert',JSON.stringify(items)]);
 await concurrentB.query('begin');await concurrentB.query('set role authenticated');await concurrentB.query('select public.attendance_management_reauthentication_target($1,$2::jsonb)',['upsert',JSON.stringify(items)]);
 const pid=(await membership.query('select pg_backend_pid() pid')).rows[0].pid;
 const inserting=membership.query('insert into company_members(company_id,user_id,role) values($1,$2,$3)',[B,U,'owner']);
 let blocked=false;for(let i=0;i<100;i++){if(await q('select cardinality(pg_blocking_pids($1))>0 v',[pid])){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}eq(blocked,true,'Concurrent membership insertion demonstrably waits');
 await concurrentA.query('rollback');await concurrentB.query('rollback');await inserting;
 await reject(()=>getTarget('upsert',items),{code:'42501',message:'attendance_reauthentication_single_company_required'});await client.query('delete from company_members where company_id=$1 and user_id=$2',[B,U]);
 await client.query("update private.reauthentication_rollout set enabled=false where scope='attendance_management'");
 await reject(async()=>exec(await readFile('tool/staged/attendance_reauthentication_restore_unused.sql','utf8')),{code:'P0001',message:'attendance_reauthentication_unused_restore_only'});await exec('rollback');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,actual_force_body:true,old_broad_suites_replayed:false,production_changed:false}));
 }finally{for(const c of second)await c.end();}
`;
 const proof=join(folder,'proof.mjs');await writeFile(proof,prefix+unit+tail);
 if(process.env.SKO_ATTENDANCE_STEPUP_EMIT_ONLY){await writeFile(process.env.SKO_ATTENDANCE_STEPUP_EMIT_ONLY,prefix+unit+tail);}else{
 const doc=resolve(here,'../supervisor-document-candidate'),admin=resolve(here,'../attendance-admin-override-candidate');
 const execution=spawnSync(process.execPath,[proof,process.argv[2]],{stdio:'inherit',env:{...process.env,SKO_DOCUMENT_CANDIDATE:resolve(doc,'document-signature-and-edit.sql.review-only'),SKO_DOCUMENT_TRIGGER_PINS:resolve(doc,'trigger-source-pins.json'),SKO_ADMIN_CANDIDATE:resolve(admin,'attendance-admin-override.sql.review-only'),SKO_ADMIN_ORIGINALS:resolve(admin,'native-original-sources.sql'),SKO_MANAGEMENT_REGISTERED_SQL:resolve(management,'management-registered-allowances.sql.review-only'),SKO_MANAGEMENT_READER_SOURCES:resolve(management,'native-reader-sources.json')}});if(execution.error)throw execution.error;process.exitCode=execution.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
