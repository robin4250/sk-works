import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';import{pathToFileURL}from'node:url';
const src=path.resolve(process.env.SKO_DOCUMENT_SOURCE??'.');
const read=f=>fs.readFile(path.join(src,f),'utf8');
const native=process.env.SKO_DOCUMENT_ADMIN_FIXTURE_URL;let db,close;
if(native){
 const u=new URL(native);if(u.hostname!=='127.0.0.1'||u.pathname!=='/sko_document_admin_fixture'||u.search||u.hash){throw Error('dedicated fixture required');}
 const pg=await import(pathToFileURL(path.resolve(process.argv[2])));const c=new(pg.Client??pg.default.Client)({connectionString:native});await c.connect();
 db={query:(...a)=>c.query(...a),exec:s=>c.query(s)};close=()=>c.end();
 assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await db.query("select count(*)::int n from pg_namespace where nspname not in('public','information_schema') and nspname !~ '^pg_'")).rows[0].n,0);
}else{const{PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])));db=new PGlite();close=()=>db.close();}
const uid=n=>`70000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const[company,worker,req,owner,reviewer,target,sid,rsid]=[1,2,3,4,5,6,7,8].map(uid);
const photo=`${company}/${worker}/${req}/${target}/old.png`;
let count=0;const pass=s=>{count++;console.log(`PASS ${count}: ${s}`)};
async function actor(id,session){await db.exec('reset role');await db.query("select set_config('fixture.uid',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,session_id:session,role:'authenticated',is_anonymous:false})]);await db.exec('set role authenticated');}
async function rpc(a,d={}){return(await db.query('select public.worker_document_admin_self_correction($1,$2::jsonb) v',[a,JSON.stringify(d)])).rows[0].v;}
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
 insert into public.company_members values('${company}','${owner}','admin'),('${company}','${reviewer}','admin');
 insert into public.workers values('${worker}','${company}','${owner}','active');
 insert into public.document_requirements(id,company_id,name) values('${req}','${company}','Synthetic document');
 insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,notes,attachment_path,updated_by)
 values('${target}','${company}','${worker}','${req}','submitted','retained original','${photo}','${owner}');
 insert into storage.objects(bucket_id,name) values('worker-documents','${photo}');`);
 const original=await status();
 await db.exec(await fs.readFile(new URL('../../candidates/worker_document_admin_self_correction_20261031.sql.review-only',import.meta.url),'utf8'));
 const identity={company_id:company,target_id:target};
 await actor(owner,sid);
 assert.equal((await rpc('capability',identity)).available,false);
 const command={...identity,request_id:uid(20),expected_snapshot:original,
  fields:{attachment_paths:[photo],expires_at:'2030-01-01',notes:'corrected metadata'},reason:'Input correction'};
 await assert.rejects(rpc('correct',command));assert.deepEqual(await status(),original);
 pass('OFF installation changes no original and cannot correct');
 await db.exec('reset role');await db.exec('update private.worker_document_admin_correction_state set enabled=true');
 await actor(reviewer,rsid);await assert.rejects(rpc('correct',command));
 pass('another administrator cannot use the administrator-own purpose');
 await db.exec('reset role');await db.exec(`update public.company_members set role='employee' where user_id='${owner}';
 insert into public.member_feature_permissions(company_id,user_id,can_manage_people) values('${company}','${owner}',true)`);
 await actor(owner,sid);await assert.rejects(rpc('correct',command));
 pass('delegated employee cannot acquire administrator self correction');
 await db.exec('reset role');await db.exec(`update public.company_members set role='manager' where user_id='${owner}';
 update public.member_feature_permissions set can_manage_people=false where user_id='${owner}'`);
 await actor(owner,sid);await assert.rejects(rpc('correct',command));
 pass('manager requires existing people permission as well as role');
 await db.exec('reset role');await db.exec(`update public.member_feature_permissions set can_manage_people=true where user_id='${owner}'`);
 await actor(owner,sid);await assert.rejects(rpc('correct',{...command,fields:{...command.fields,attachment_paths:['new-object']}}));
 await assert.rejects(rpc('correct',{...command,reason:''}));
 await assert.rejects(rpc('correct',{...command,expected_snapshot:{...original,notes:'stale'}}));
 await assert.rejects(rpc('correct',{...command,fields:{...command.fields,status:'verified'}}));
 pass('new photos, empty reason, stale full snapshot and extra verification fields rejected');
 await db.exec('reset role');await db.exec('create table private.worker_document_changes(target_id uuid,status text)');
 await db.query("insert into private.worker_document_changes values($1,'pending')",[target]);
 await actor(owner,sid);await assert.rejects(rpc('correct',command));
 await db.exec('reset role');await db.exec('delete from private.worker_document_changes');
 pass('old personal pending requests are preserved and block administrator correction');
 await actor(owner,sid);
 const cancelled={...identity,request_id:uid(21)};
 assert.equal((await rpc('get',cancelled)).status,'unknown');
 assert.equal((await rpc('reconcile_cancel',cancelled)).status,'cancelled');
 await assert.rejects(rpc('correct',{...command,request_id:uid(21)}));
 pass('unknown is not success; ID-only cancellation fences delayed original commands');
 const receipt=await rpc('correct',command);assert.equal(receipt.status,'applied');
 assert.deepEqual(await rpc('correct',command),receipt);
 await assert.rejects(rpc('correct',{...command,reason:'different request body'}));
 const revised=await status();assert.equal(revised.expires_at,'2030-01-01');assert.equal(revised.original_verified,false);
 assert.equal(revised.attachment_path,photo);assert.equal(revised.notes,'corrected metadata');
 pass('fixed-ID atomic correction saves metadata once without approving original verification');
 await db.exec('reset role');
 const ledger=(await db.query('select * from private.worker_document_admin_corrections where request_id=$1',[uid(20)])).rows[0];
 assert.deepEqual(ledger.before_snapshot,original);assert.deepEqual(ledger.after_snapshot,revised);
 assert.equal((await db.query('select count(*)::int n from private.worker_document_admin_correction_tickets')).rows[0].n,0);
 await assert.rejects(db.query('delete from private.worker_document_admin_corrections where request_id=$1',[uid(20)]));
 pass('full original/revision/reason/SID retained in append-only archive and one-use ticket consumed');
 await db.exec('begin');
 await db.exec('alter table public.worker_document_statuses disable trigger zzz_worker_document_admin_correction_ticket');
 await actor(owner,sid);
 await assert.rejects(rpc('correct',{...command,request_id:uid(35),expected_snapshot:revised}));
 await db.exec('rollback');assert.deepEqual(await status(),revised);
 pass('disabled ticket guard cannot silently bypass protected write; entire correction rolls back');
 await db.exec('reset role');
 assert.equal((await db.query("select has_function_privilege('authenticated','public.worker_document_admin_self_correction(text,jsonb)','EXECUTE') v")).rows[0].v,true);
 for(const role of ['anon','service_role']){
  assert.equal((await db.query('select has_function_privilege($1,$2,\'EXECUTE\') v',[role,'public.worker_document_admin_self_correction(text,jsonb)'])).rows[0].v,false);
 }
 assert.equal((await db.query("select has_function_privilege('authenticated','private.worker_document_admin_correction_ticket_guard()','EXECUTE') v")).rows[0].v,false);
 pass('public-only defaults narrowed on new endpoint; private writer guard receives no authenticated grant');
 await actor(owner,sid);await assert.rejects(db.exec('select * from private.worker_document_admin_corrections'));
 await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[sid]);
 await actor(owner,sid);await assert.rejects(rpc('get',{...identity,request_id:uid(20)}));
 await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2,null)',[uid(30),owner]);
 await actor(owner,uid(30));assert.deepEqual(await rpc('get',{...identity,request_id:uid(20)}),receipt);
 pass('no direct archive access; revoked SID rejected and legitimate new live SID reads same opaque receipt');
 await db.exec('reset role');await db.exec('begin');
 await db.query('delete from public.worker_document_statuses where id=$1',[target]);
 await actor(owner,uid(30));assert.deepEqual(await rpc('get',{...identity,request_id:uid(20)}),receipt);
 await db.exec('rollback');
 pass('committed ID-only receipt survives later status removal without relaxing current worker or company authority');
 await db.exec('reset role');await db.exec('update private.worker_document_admin_correction_state set enabled=false');
 await actor(owner,uid(30));assert.deepEqual(await rpc('reconcile_cancel',{...identity,request_id:uid(20)}),receipt);
 await assert.rejects(rpc('correct',{...command,request_id:uid(31),expected_snapshot:revised}));
 pass('OFF stops new writes while scoped ID-only reconciliation preserves committed outcome');
 if(native){
  const pg=await import(pathToFileURL(path.resolve(process.argv[2])));
  const other=new(pg.Client??pg.default.Client)({connectionString:native});await other.connect();
  try{
   const pid=(await other.query('select pg_backend_pid() pid')).rows[0].pid;
   await other.query("select set_config('fixture.uid',$1,false),set_config('request.jwt.claims',$2,false)",
    [owner,JSON.stringify({sub:owner,session_id:uid(30),role:'authenticated',is_anonymous:false})]);
   await other.query('set role authenticated');
   const otherRpc=(a,d)=>other.query('select public.worker_document_admin_self_correction($1,$2::jsonb) v',[a,JSON.stringify(d)]);
   async function observedWait(){
    for(let n=0;n<100;n++){
     const waiting=(await db.query("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted) v",[pid])).rows[0].v;
     if(waiting){return;}
     await new Promise(resolve=>setTimeout(resolve,25));
    }
    throw Error('second connection never observed waiting at request barrier');
   }
   await db.exec('reset role');await db.exec('update private.worker_document_admin_correction_state set enabled=true');
   const concurrent={...command,request_id:uid(40),expected_snapshot:await status(),reason:'concurrent correction'};
   await actor(owner,uid(30));await db.exec('begin');
   const applied=await rpc('correct',concurrent);
   const waiting=otherRpc('reconcile_cancel',{...identity,request_id:uid(40)});
   await observedWait();await db.exec('commit');
   assert.deepEqual((await waiting).rows[0].v,applied);
   pass('Native two connections: cancellation actually waits for in-flight correction and returns its committed receipt');
   const afterConcurrent=await status();
   await db.exec('begin');await rpc('reconcile_cancel',{...identity,request_id:uid(41)});
   const delayed=otherRpc('correct',{...concurrent,request_id:uid(41),expected_snapshot:afterConcurrent});
   // Attach a rejection observer before the COMMIT can release the barrier.
   const rejected=assert.rejects(delayed,error=>error.code==='23505');
   await observedWait();await db.exec('commit');await rejected;
   assert.deepEqual(await status(),afterConcurrent);
   pass('Native two connections: delayed correction actually waits for cancellation and cannot resurrect the fixed ID');
  }finally{await db.exec('reset role');await db.exec('rollback');await other.end();}
 }
 console.log(JSON.stringify({checks:count,fixture:native?'Native PostgreSQL17':'PGlite',production:false,real_storage:false}));
}finally{await close();}
