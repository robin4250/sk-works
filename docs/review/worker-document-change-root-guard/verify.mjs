// Disposable fixture only. Actual helper bodies; synthetic surrounding Auth,
// memberships, users, sessions and Storage objects. No production connection.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import assert from 'node:assert/strict';import {pathToFileURL}from'node:url';import{spawnSync}from'node:child_process';
process.umask(0o077);
const src=path.resolve(process.env.SKO_DOCUMENT_SOURCE??'.');
const here=path.dirname(new URL(import.meta.url).pathname);const read=f=>fs.readFile(path.join(src,f),'utf8');
const native=process.env.SKO_DOCUMENT_GUARD_FIXTURE_URL;let db,close;
if(native){const u=new URL(native);if(u.hostname!=='127.0.0.1'||u.pathname!=='/sko_document_guard_fixture'||u.search||u.hash)throw Error('dedicated fixture required');const pg=await import(pathToFileURL(path.resolve(process.argv[2])));const c=new(pg.Client??pg.default.Client)({connectionString:native});await c.connect();db={query:(...a)=>c.query(...a),exec:s=>c.query(s)};close=()=>c.end();assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);assert.equal((await db.query("select count(*)::int n from pg_namespace where nspname not in('public','information_schema') and nspname !~ '^pg_'")).rows[0].n,0);}else{const{PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])));db=new PGlite();close=()=>db.close();}
const uid=n=>`70000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,worker,req,owner,reviewer,target,sid,rsid]=[1,2,3,4,5,6,7,8].map(uid);
const photo=`${company}/${worker}/${req}/${target}/old.png`;
let count=0;const pass=s=>{count++;console.log(`PASS ${count}: ${s}`)};
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'sko-document-guard-'));
const catalog=(await fs.readFile(path.join(here,'catalog.sql'),'utf8')).trim().replace(/;$/,'');
async function actor(id,session){await db.exec('reset role');await db.query("select set_config('fixture.uid',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,session_id:session,role:'authenticated',is_anonymous:false})]);await db.exec('set role authenticated');}
async function rpc(a,d={}){return(await db.query('select public.worker_document_change($1,$2::jsonb) v',[a,JSON.stringify(d)])).rows[0].v;}
const capture=async()=>(await db.query("select q.snapshot,encode(sha256(convert_to(q.snapshot::text,'UTF8')),'hex') snapshot_sha256 from ("+catalog+")q")).rows[0];
const snapshot=async()=>(await capture()).snapshot;
const status=async()=>(await db.query('select to_jsonb(s) v from public.worker_document_statuses s where id=$1',[target])).rows[0].v;
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema storage;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create table public.companies(id uuid primary key,synthetic_sequence bigint generated always as identity);
 create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.workers(id uuid primary key,company_id uuid references public.companies(id) on delete cascade,user_id uuid,status text not null default 'active');
 create table public.member_feature_permissions(company_id uuid,user_id uuid,
 can_approve_daily_report_edits boolean default false,can_manage_attendance boolean default false,can_manage_people boolean default false,
 can_view_invoices boolean default false,can_manage_invoices boolean default false,can_view_admin_site_data boolean default false,
 can_manage_admin_site_data boolean default false,can_manage_payroll boolean default false,can_manage_partner_chat boolean default false,primary key(company_id,user_id));
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;
 create table storage.buckets(id text primary key,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 insert into storage.buckets values('worker-documents',false,52428800,null);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;
 create policy synthetic_fixture_read on storage.objects for select to authenticated using(true);
 create policy synthetic_fixture_update on storage.objects for update to authenticated using(true) with check(true);
 create policy synthetic_fixture_delete on storage.objects for delete to authenticated using(true);
 grant usage on schema auth,private,storage to authenticated;
 grant select,update,delete on storage.objects to authenticated;
 alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role;`);
 await db.exec(await read('tool/security/worker_document_change_session/baseline.sql'));
 for(const m of ['20260918133000_add_worker_document_checklist.sql','20260918144500_add_worker_document_status_history.sql','20260919023500_harden_worker_document_rls.sql','20261003121632_allow_self_document_registration.sql','20261010222524_worker_document_multiple_photos.sql'])await db.exec(await read('supabase/migrations/'+m));
 await db.exec(`grant select on public.companies,public.company_members,public.workers,public.document_requirements,public.worker_document_status_history to authenticated;
 grant select,insert,update,delete on public.worker_document_statuses to authenticated;
 insert into public.companies(id) values('${company}');insert into auth.users(id) values('${owner}'),('${reviewer}');
 insert into auth.sessions values('${sid}','${owner}',null),('${rsid}','${reviewer}',null);
 insert into public.company_members values('${company}','${owner}','employee'),('${company}','${reviewer}','admin');
 insert into public.workers values('${worker}','${company}','${owner}','active');
 insert into public.document_requirements(id,company_id,name) values('${req}','${company}','Synthetic document');
 insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,notes,attachment_path,updated_by)
 values('${target}','${company}','${worker}','${req}','submitted','retained original','${photo}','${owner}');
 insert into storage.objects(bucket_id,name) values('worker-documents','${photo}');`);
 const firstCapture=await capture(),before=firstCapture.snapshot,original=await status();await fs.writeFile(path.join(temp,'before.json'),JSON.stringify(firstCapture));
 const out=path.join(temp,'bundle');const built=spawnSync('python3',[path.join(here,'prepare.py'),'--before',path.join(temp,'before.json'),'--catalog',path.join(here,'catalog.sql'),'--candidate-dir',path.join(src,'docs/candidates/worker_document_change_session_20261029'),'--output',out],{encoding:'utf8'});assert.equal(built.status,0,built.stderr);
 const install=await fs.readFile(path.join(out,'install-off.guarded.sql.review-only'),'utf8');const restore=await fs.readFile(path.join(out,'restore-unused.guarded.sql.review-only'),'utf8');
 const tampered=path.join(temp,'tampered');await fs.mkdir(tampered);await fs.writeFile(path.join(tampered,'install.sql.review-only'),await read('docs/candidates/worker_document_change_session_20261029/install.sql.review-only')+'\n-- changed');await fs.writeFile(path.join(tampered,'restore-unused.sql.review-only'),await read('docs/candidates/worker_document_change_session_20261029/restore-unused.sql.review-only'));
 const rejected=spawnSync('python3',['-O',path.join(here,'prepare.py'),'--before',path.join(temp,'before.json'),'--catalog',path.join(here,'catalog.sql'),'--candidate-dir',tampered,'--output',path.join(temp,'must-not-exist')],{encoding:'utf8'});assert.notEqual(rejected.status,0);await assert.rejects(fs.access(path.join(temp,'must-not-exist')));pass('Python optimization cannot disable immutable successor source validation');

 await db.exec("comment on function private.account_access_allowed() is 'synthetic drift'");await assert.rejects(db.exec(install));await db.exec('rollback');assert.equal((await db.query("select to_regclass('private.worker_document_changes') v")).rows[0].v,null);await db.exec('comment on function private.account_access_allowed() is null');pass('preexisting dependency drift rejects before any new object');
 for(const mutation of [
  "grant execute on function private.require_reauthentication_session() to authenticated",
  "grant authenticated to service_role",
  "create function public.synthetic_unknown_dependency() returns boolean language sql as $$select true$$",
  "alter policy synthetic_fixture_read on storage.objects using(false)",
  "alter default privileges for role postgres in schema private grant execute on functions to authenticated",
  "update storage.buckets set public=true where id='worker-documents'",
 ]){await db.exec('begin');await db.exec(mutation);await assert.rejects(db.exec(install));await db.exec('rollback');assert.equal((await db.query("select to_regclass('private.worker_document_changes') v")).rows[0].v,null);}
 pass('unknown function, helper ACL, inherited authority, Storage policy, private defaults and bucket exposure all fail closed');
 await db.exec('create trigger zz_worker_document_change_guard before update on public.worker_document_statuses for each row execute function private.normalize_worker_document_photos()');
 await assert.rejects(db.exec(install));await db.exec('rollback');await db.exec('drop trigger zz_worker_document_change_guard on public.worker_document_statuses');pass('same-name existing trigger is rejected rather than hidden by after-install exclusion');
 await db.exec("alter table public.worker_document_statuses add column synthetic_extra boolean");await assert.rejects(db.exec(install));await db.exec('rollback');await db.exec('alter table public.worker_document_statuses drop column synthetic_extra');
 // Dropped-column catalog remains a real drift: capture a new reviewed fixture
 // baseline, rather than pretending add/drop restored all metadata bytes.
 const refreshedCapture=await capture(),refreshed=refreshedCapture.snapshot;await fs.writeFile(path.join(temp,'before-refreshed.json'),JSON.stringify(refreshedCapture));
 const out2=path.join(temp,'bundle-refreshed');const b2=spawnSync('python3',[path.join(here,'prepare.py'),'--before',path.join(temp,'before-refreshed.json'),'--catalog',path.join(here,'catalog.sql'),'--candidate-dir',path.join(src,'docs/candidates/worker_document_change_session_20261029'),'--output',out2],{encoding:'utf8'});assert.equal(b2.status,0,b2.stderr);
 const finalInstall=await fs.readFile(path.join(out2,'install-off.guarded.sql.review-only'),'utf8'),finalRestore=await fs.readFile(path.join(out2,'restore-unused.guarded.sql.review-only'),'utf8'),enable=await fs.readFile(path.join(out2,'enable-separately-approved.guarded.sql.review-only'),'utf8');
 await db.exec(finalInstall);assert.deepEqual(await status(),original);assert.deepEqual(await snapshot(),refreshed);pass('guarded OFF install preserves originals and full existing catalog');
 assert.equal((await db.query("select has_function_privilege('service_role','public.worker_document_change(text,jsonb)','EXECUTE') v")).rows[0].v,false);assert.equal((await db.query("select has_function_privilege('authenticated','public.worker_document_change(text,jsonb)','EXECUTE') v")).rows[0].v,true);pass('actual public-only default EXECUTE is narrowed for new endpoint only');
 await db.exec('begin');await db.exec('alter table private.worker_document_changes add column synthetic_unreviewed text');await assert.rejects(db.exec(finalRestore));await db.exec('rollback');pass('new-module column drift blocks unused restoration despite the older limited seal');
 await actor(owner,sid);await assert.rejects(rpc('capability'));await db.exec('reset role');await db.exec(finalRestore);assert.deepEqual(await snapshot(),refreshed);assert.deepEqual(await status(),original);pass('OFF denies request operations and guarded unused restore preserves originals');
 await db.exec(finalInstall);await db.exec(enable);pass('separate activation receipt and full catalog gate accepts only the exact unused OFF module in the disposable fixture');await actor(owner,sid);
 assert.deepEqual(await rpc('capability'),{version:1,change_requests_available:true,new_upload_available:false,max_photos:20,self_approval_allowed:false});
 const payload={request_id:uid(20),status_id:target,expected_updated_at:original.updated_at,proposed:{attachment_paths:[photo],expires_at:'2030-01-01',notes:'approved synthetic revision'}};
 await rpc('prepare',payload);await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sid]);const fresh=uid(9);await db.query('insert into auth.sessions values($1,$2,null)',[fresh,owner]);await actor(owner,sid);await assert.rejects(rpc('submit',{request_id:uid(20)}));await actor(owner,fresh);await rpc('capability');await rpc('submit',{request_id:uid(20)});await db.exec('reset role');assert.equal((await db.query('select created_session_id::text sid from private.worker_document_changes where id=$1',[uid(20)])).rows[0].sid,sid);assert.equal((await db.query("select session_id::text sid from private.worker_document_change_events where request_id=$1 and action='submit'",[uid(20)])).rows[0].sid,fresh);await actor(owner,fresh);pass('expired/revoked old SID cannot submit; explicit live new SID resumes without rewriting creation SID');assert.deepEqual(await status(),original);await assert.rejects(rpc('approve',{request_id:uid(20)}));pass('v1 existing-photo expiry/notes proposal leaves official content unchanged; self approval denied');
 await actor(reviewer,rsid);assert.equal((await rpc('approve',{request_id:uid(20)})).status,'approved');assert.equal((await status()).expires_at,'2030-01-01');assert.equal((await status()).notes,'approved synthetic revision');assert.equal((await status()).attachment_path,photo);pass('different currently authorized reviewer applies existing-photo proposal once');
 await db.exec('reset role');await db.exec('update private.worker_document_change_rollout set enabled=false');await assert.rejects(db.exec(finalRestore));await db.exec('rollback');assert.ok((await db.query('select count(*)::int n from private.worker_document_changes')).rows[0].n>0);pass('after-use restore refuses and preserves request/event/history');
 const record={fixture:native?'Native PostgreSQL17':'PGlite',checks:count,auth:'synthetic surrounding Auth using pinned actual helper bodies',production:false,actual_storage:false,original_function_count:refreshed.functions.length};await fs.writeFile(path.join(here,'last-fixture-receipt.json'),JSON.stringify(record,null,2)+'\n');console.log(JSON.stringify(record));
}finally{await close();await fs.rm(temp,{recursive:true,force:true});}
