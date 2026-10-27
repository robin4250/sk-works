// Dedicated synthetic PostgreSQL/PGlite only. No real Supabase, sessions or files.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const sourceRoot=process.env.SKO_SOURCE_ROOT?path.resolve(process.env.SKO_SOURCE_ROOT):new URL('../',import.meta.url);
const read=p=>fs.readFile(typeof sourceRoot==='string'?path.join(sourceRoot,p):new URL(p,sourceRoot),'utf8');
const changeSql=await fs.readFile(new URL('../docs/candidates/qualification_admin_record_changes_20261027.sql.review-only',import.meta.url),'utf8');
const native=process.env.SKO_QUALIFICATION_RECORD_FIXTURE_URL;
let db,close;
if(native){
 const u=new URL(native),name='sko_qualification_record_fixture';
 if(u.hostname!=='127.0.0.1'||u.pathname!==`/${name}`||u.search||u.hash||!['postgres:','postgresql:'].includes(u.protocol))throw Error('dedicated local fixture required');
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href),Client=mod.Client??mod.default?.Client;
 const c=new Client({connectionString:native});
 if(c.connectionParameters.host!=='127.0.0.1'||c.connectionParameters.database!==name)throw Error('effective fixture connection mismatch');
 await c.connect();await c.query("set statement_timeout='20s';set lock_timeout='5s'");
 db={query:(...args)=>c.query(...args),exec:s=>c.query(s)};close=()=>c.end();
 assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await db.query("select count(*)::int n from pg_namespace where nspname not in('public','information_schema') and nspname !~ '^pg_'")).rows[0].n,0,'empty dedicated fixture required');
 await db.exec("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role;end if;end$$");
}else{
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();close=()=>db.close();
}
try{
 for(const p of ['tool/fixtures/qualification_photo_submission/schema.sql','tool/fixtures/qualification_photo_submission/live_functions.sql','supabase/migrations/20261010222157_add_qualification_certificate_extra_photos.sql','supabase/migrations/20261010222753_protect_qualification_photo_snapshots.sql','supabase/migrations/20261010233011_personal_qualification_photo_submission.sql']){
  let sql=await read(p);if(native)sql=sql.replace('create role anon;create role authenticated;create role service_role;','');await db.exec(sql);
 }
 const verifier=await read('tool/verify_qualification_admin_saved_photos.mjs');
 const bootstrap=verifier.match(/await db\.exec\(`(alter table workers add column status[\s\S]*?)`\);/);assert.ok(bootstrap);
 await db.exec(bootstrap[1]);
 await db.exec(`create table public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_people boolean);
 create function private.require_reauthentication_session() returns void language plpgsql security definer set search_path='' as $$begin
  if auth.uid() is null or coalesce(current_setting('test.live_sid',true),'true')<>'true' then raise exception 'live session required' using errcode='42501';end if;end$$;
 create or replace function private.has_company_feature(c uuid,f text) returns boolean language sql stable security definer set search_path='' as $$select coalesce(current_setting('test.manage_people',true),'true')='true' and exists(select 1 from public.company_members m where company_id=c and user_id=auth.uid() and (role in('owner','admin') or (role='manager' and exists(select 1 from public.member_feature_permissions fp where fp.company_id=c and fp.user_id=m.user_id and fp.can_manage_people))))$$;
 grant delete on public.worker_qualifications to authenticated;
 create policy fixture_admin_delete on public.worker_qualifications for delete to authenticated using(private.has_company_feature(company_id,'can_manage_people'));`);
 await db.exec(await read('docs/candidates/qualification_admin_saved_photos_20261019.sql.review-only'));
 await db.exec(await read('docs/candidates/qualification_admin_photo_baseline_20261021.sql.review-only'));
 console.log('PREREQUISITE', (await db.query("select md5(prosrc) personal_md5 from pg_proc where oid='private.personal_qualification_submission(text,jsonb)'::regprocedure")).rows[0]);
 await db.exec(`create table private.worker_qualification_history(id uuid primary key default gen_random_uuid(),company_id uuid not null,worker_id uuid not null,source_id uuid not null,attachment_path text,snapshot jsonb not null,operation text not null,changed_by uuid,changed_at timestamptz not null default clock_timestamp());
create function private.capture_official_qualification_history() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and to_jsonb(old)=to_jsonb(new) then return new; end if;
 if tg_op in ('UPDATE','DELETE') then
  insert into private.worker_qualification_history(company_id,worker_id,source_id,attachment_path,snapshot,operation,changed_by)
  values(old.company_id,old.worker_id,old.id,old.attachment_path,to_jsonb(old),case when tg_op='DELETE' then 'delete' else 'before_update' end,auth.uid());
 end if;
 if tg_op<>'DELETE' then
  insert into private.worker_qualification_history(company_id,worker_id,source_id,attachment_path,snapshot,operation,changed_by)
  values(new.company_id,new.worker_id,new.id,new.attachment_path,to_jsonb(new),lower(tg_op),auth.uid());
  return new;
 end if;
 return old;
end$$;
create trigger capture_official_qualification_history after insert or update or delete on public.worker_qualifications for each row execute function private.capture_official_qualification_history();`);
 await db.exec(changeSql);
 const id=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [company,admin,reviewer,manager,user,worker,master,target,foreignCompany,foreignAdmin]=[1,2,3,4,5,6,7,8,9,10].map(id);
 const front=`${company}/${worker}/${master}/legacy/front.jpg`,back=`${company}/${worker}/${master}/legacy/back.jpg`;
 await db.query('insert into companies values($1),($2)',[company,foreignCompany]);
 await db.query("insert into company_members values($1,$2,'admin'),($1,$3,'admin'),($1,$4,'manager'),($1,$5,'member'),($6,$7,'admin')",[company,admin,reviewer,manager,user,foreignCompany,foreignAdmin]);
 await db.query('insert into member_feature_permissions values($1,$2,true)',[company,manager]);
 await db.query('insert into company_approval_assignees values($1,$2)',[company,manager]);
 await db.query('insert into workers(id,company_id,user_id) values($1,$2,$3)',[worker,company,user]);
 await db.query("insert into qualification_master values($1,$2,'Synthetic skill',false)",[master,company]);
 await db.query("insert into storage.objects(bucket_id,name)values('qualification-certificates',$1),('qualification-certificates',$2)",[front,back]);
 await db.query("insert into worker_qualifications(id,company_id,worker_id,qualification_master_id,certificate_number,issuer,notes,attachment_path,attachment_back_path)values($1,$2,$3,$4,'original','issuer','original notes',$5,$6)",[target,company,worker,master,front,back]);
 const actor=async uid=>{await db.exec('reset role');await db.query("select set_config('test.uid',$1,false)",[uid??'']);await db.exec('set role authenticated');};
 const owner=()=>db.exec('reset role');
 const rpc=async(action,data={})=>(await db.query('select private.personal_qualification_submission($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;
 const change=async(action,data={})=>rpc(action,{company_id:company,...data});
 const row=async()=>{await owner();return (await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0]?.v;};
 const proposal={certificate_number:'updated certificate',issuer:'updated issuer',issued_at:'2026-10-01',expires_at:null,notes:'updated notes'};
 const initial=await row();
 const prepare=async(n,operation='metadata',expected=initial)=>change('prepare_admin_record_change',{request_id:id(n),target_id:target,operation,reason:'Synthetic correction reason',expected_snapshot:expected,proposed:operation==='metadata'?proposal:null});
 await actor(admin);assert.equal((await change('admin_record_change_capability')).available,true);
 await actor(user);assert.equal((await change('admin_record_change_capability')).available,false);
 await assert.rejects(change('inspect_admin_record',{target_id:target}),e=>e.code==='42501');
 await actor(foreignAdmin);await assert.rejects(prepare(20),e=>e.code==='42501');
 await actor(admin);await db.exec("set test.live_sid='false'");await assert.rejects(prepare(20),e=>e.code==='42501');await db.exec("set test.live_sid='true'");
 await db.exec("set test.active='false'");await assert.rejects(prepare(20),e=>e.code==='42501');await db.exec("set test.active='true'");
 await assert.rejects(prepare(20,'metadata',{...initial,notes:'stale'}),e=>e.code==='40001');
 await assert.rejects(change('prepare_admin_record_change',{request_id:id(20),target_id:target,reason:'x',expected_snapshot:initial,proposed:proposal}),e=>e.code==='22023');
 const draft=await prepare(20);assert.equal(draft.status,'draft');assert.equal(draft.operation,'metadata');
 assert.deepEqual(await prepare(20),draft);assert.deepEqual(await row(),initial);
 await actor(admin);await assert.rejects(change('prepare_admin_record_change',{request_id:id(20),target_id:target,operation:'metadata',reason:'conflicting reason',expected_snapshot:initial,proposed:proposal}),e=>e.code==='23505');
 assert.equal((await change('submit_admin_record_change',{id:id(20)})).status,'pending');
 await assert.rejects(change('approve_admin_record_change',{id:id(20)}),e=>e.code==='42501');
 await actor(reviewer);const saved=await change('approve_admin_record_change',{id:id(20)});assert.equal(saved.status,'approved');
 const metadata=await row();assert.equal(metadata.certificate_number,proposal.certificate_number);assert.equal(metadata.attachment_path,front);assert.equal(metadata.attachment_back_path,back);
 await actor(reviewer);assert.equal((await change('approve_admin_record_change',{id:id(20)})).status,'approved');
 await assert.rejects(db.query("update worker_qualifications set notes='direct bypass' where id=$1",[target]),e=>e.code==='42501');
 await assert.rejects(db.query('delete from worker_qualifications where id=$1',[target]),e=>e.code==='42501');
 await actor(manager);assert.equal((await change('admin_record_change_capability')).available,true);
 await prepare(21,'metadata',metadata);await change('submit_admin_record_change',{id:id(21)});
 await owner();await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[manager]);
 await actor(reviewer);await assert.rejects(change('approve_admin_record_change',{id:id(21)}),e=>e.code==='42501');
 await owner();await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[manager]);
 await actor(reviewer);await change('reject_admin_record_change',{id:id(21),reason:'Use current details'});
 await actor(admin);await prepare(22,'delete',metadata);await change('submit_admin_record_change',{id:id(22)});
 await actor(reviewer);await change('approve_admin_record_change',{id:id(22)});assert.equal(await row(),undefined);
 assert.equal((await db.query("select count(*)::int n from private.qualification_submissions where id=$1 and status='approved' and previous->>'attachment_path'=$2",[id(22),front])).rows[0].n,1);
 assert.equal((await db.query("select count(*)::int n from private.worker_qualification_history where source_id=$1 and operation='delete' and snapshot->>'attachment_path'=$2",[target,front])).rows[0].n,1,'official deleted-row snapshot retained');
 assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,2,'no photo object deletion');
 assert.ok((await db.query("select count(*)::int n from private.qualification_photo_history where paths @> array[$1::text]",[front])).rows[0].n>0,'old photo references retained');
 assert.equal((await db.query('select count(*)::int n from private.qualification_approved_write_permits')).rows[0].n,0,'single use permits consumed');
 await actor(admin);assert.equal((await prepare(22,'delete',metadata)).status,'approved','same request retry after deletion');
 await actor(reviewer);assert.equal((await change('approve_admin_record_change',{id:id(22)})).status,'approved');
 await owner();assert.equal((await db.query("select count(*)::int n from pg_proc where oid in('private.admin_qualification_record_change(text,jsonb)'::regprocedure,'private.qualification_record_change_result(private.qualification_submissions)'::regprocedure) and (has_function_privilege('anon',oid,'EXECUTE') or has_function_privilege('authenticated',oid,'EXECUTE') or has_function_privilege('service_role',oid,'EXECUTE'))")).rows[0].n,0,'private helpers not directly callable');
 console.log(`PASS qualification record changes (${native?'native PostgreSQL17':'PGlite'}): role/company/live session, snapshot CAS, immutable retries, separate approval, metadata/photo retention, direct-write denial and audited deletion`);
}finally{await close();}
