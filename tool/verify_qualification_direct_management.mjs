// Synthetic, dedicated PostgreSQL17/PGlite fixture. No real user, files or Auth.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const sourceRoot=process.env.SKO_SOURCE_ROOT?path.resolve(process.env.SKO_SOURCE_ROOT):new URL('../',import.meta.url);
const read=p=>fs.readFile(typeof sourceRoot==='string'?path.join(sourceRoot,p):new URL(p,sourceRoot),'utf8');
const own=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
const native=process.env.SKO_QUALIFICATION_MANAGEMENT_FIXTURE_URL;
let db,close;
if(native){
 const u=new URL(native),name='sko_qualification_management_fixture';
 if(u.hostname!=='127.0.0.1'||u.pathname!==`/${name}`||u.search||u.hash||!['postgres:','postgresql:'].includes(u.protocol))throw Error('dedicated local fixture required');
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href),Client=mod.Client??mod.default?.Client;
 const c=new Client({connectionString:native});
 if(c.connectionParameters.host!=='127.0.0.1'||c.connectionParameters.database!==name)throw Error('effective fixture mismatch');
 await c.connect();await c.query("set statement_timeout='20s';set lock_timeout='5s'");
 db={query:(...args)=>c.query(...args),exec:s=>c.query(s)};close=()=>c.end();
 assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await db.query("select count(*)::int n from pg_namespace where nspname not in('public','information_schema') and nspname !~ '^pg_'")).rows[0].n,0,'empty fixture required');
 await db.exec("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role;end if;end$$");
}else{
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();close=()=>db.close();
}
try{
 for(const p of ['tool/fixtures/qualification_photo_submission/schema.sql','tool/fixtures/qualification_photo_submission/live_functions.sql','supabase/migrations/20261010222157_add_qualification_certificate_extra_photos.sql','supabase/migrations/20261010222753_protect_qualification_photo_snapshots.sql','supabase/migrations/20261010233011_personal_qualification_photo_submission.sql']){
  let sql=await read(p);if(native)sql=sql.replace('create role anon;create role authenticated;create role service_role;','');await db.exec(sql);
 }
 const oldVerifier=await read('tool/verify_qualification_admin_saved_photos.mjs');
 const bootstrap=oldVerifier.match(/await db\.exec\(`(alter table workers add column status[\s\S]*?)`\);/);assert.ok(bootstrap);
 await db.exec(bootstrap[1]);
 await db.exec(`create table public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_people boolean);
 create function private.require_reauthentication_session() returns void language plpgsql security definer set search_path='' as $$begin
  if auth.uid() is null or coalesce(current_setting('test.live_sid',true),'true')<>'true' then raise exception 'live session required' using errcode='42501';end if;end$$;
 create or replace function private.has_company_feature(c uuid,f text) returns boolean language sql stable security definer set search_path='' as $$select coalesce(current_setting('test.manage_people',true),'true')='true' and exists(select 1 from public.company_members m where company_id=c and user_id=auth.uid() and (role in('owner','admin') or exists(select 1 from public.member_feature_permissions fp where fp.company_id=c and fp.user_id=m.user_id and fp.can_manage_people)))$$;
 alter table qualification_master add column is_active boolean not null default true;
 grant select on public.qualification_master to authenticated;
 grant insert,delete on public.worker_qualifications to authenticated;
 create policy fixture_admin_delete on public.worker_qualifications for delete to authenticated using(private.has_company_feature(company_id,'can_manage_people'));`);
 await db.exec(await read('supabase/migrations/20261003120833_allow_self_qualification_registration.sql'));
 await db.exec(await own('tool/fixtures/qualification_management/official_history.sql'));
 const personalBefore=(await db.query("select md5(prosrc) m from pg_proc where oid='private.personal_qualification_submission(text,jsonb)'::regprocedure")).rows[0].m;
 const sql=await own('docs/candidates/qualification_direct_management_20261027.sql.review-only');
 await db.exec(sql);
 const id=n=>`30000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [company,admin,manager,user,worker,master,target,otherCompany,otherAdmin]=[1,2,3,4,5,6,7,8,9].map(id);
 const front=`${company}/${worker}/${master}/legacy/front.jpg`,back=`${company}/${worker}/${master}/legacy/back.jpg`;
 await db.query('insert into companies values($1),($2)',[company,otherCompany]);
 await db.query("insert into company_members values($1,$2,'admin'),($1,$3,'manager'),($1,$4,'member'),($5,$6,'admin')",[company,admin,manager,user,otherCompany,otherAdmin]);
 await db.query('insert into member_feature_permissions values($1,$2,true),($1,$3,true)',[company,manager,user]);
 await db.query('insert into workers(id,company_id,user_id) values($1,$2,$3)',[worker,company,user]);
 await db.query("insert into qualification_master(id,company_id,name,expiry_required) values($1,$2,'Synthetic qualification',false)",[master,company]);
 await db.query("insert into storage.objects(bucket_id,name)values('qualification-certificates',$1),('qualification-certificates',$2)",[front,back]);
 await db.query("insert into worker_qualifications(id,company_id,worker_id,qualification_master_id,certificate_number,issuer,notes,attachment_path,attachment_back_path)values($1,$2,$3,$4,'original','issuer','original notes',$5,$6)",[target,company,worker,master,front,back]);
 const actor=async uid=>{await db.exec('reset role');await db.query("select set_config('test.uid',$1,false)",[uid??'']);await db.exec('set role authenticated');};
 const owner=()=>db.exec('reset role');
 const rpc=async(action,data={})=>(await db.query('select public.qualification_direct_management($1,$2::jsonb) v',[action,JSON.stringify({company_id:company,...data})])).rows[0].v;
 const personal=async(action,data={})=>(await db.query('select private.personal_qualification_submission($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;
 const row=async tid=>{await owner();return (await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[tid??target])).rows[0]?.v;};
 const fields={certificate_number:'updated',issuer:'issuer updated',issued_at:'2026-10-01',expires_at:null,notes:'corrected'};
 const initial=await row();
 const command={request_id:id(20),target_id:target,operation:'update',expected_snapshot:initial,fields};
 await actor(admin);assert.equal((await rpc('capability')).available,false,'installed OFF');
 await assert.rejects(rpc('apply',command),e=>e.code==='55000');
 await owner();await db.exec('update private.qualification_management_state set enabled=true');
 await actor(user);await assert.rejects(rpc('capability'),e=>e.code==='42501');
 assert.equal((await db.query("update worker_qualifications set notes='worker bypass' where id=$1 returning id",[target])).rows.length,0,'worker direct UPDATE denied');
 await actor(otherAdmin);await assert.rejects(rpc('inspect',{target_id:target}),e=>e.code==='42501');
 await actor(admin);await db.exec("set test.live_sid='false'");await assert.rejects(rpc('apply',command),e=>e.code==='42501');await db.exec("set test.live_sid='true'");
 await db.exec("set test.active='false'");await assert.rejects(rpc('apply',command),e=>e.code==='42501');await db.exec("set test.active='true'");
 await assert.rejects(rpc('apply',{...command,expected_snapshot:{...initial,notes:'stale'}}),e=>e.code==='40001');
 const changed=await rpc('apply',command);assert.equal(changed.status,'applied');assert.equal(changed.after.certificate_number,'updated');
 assert.equal(changed.after.attachment_path,front);assert.equal(changed.after.attachment_back_path,back);
 assert.deepEqual(await rpc('apply',command),changed,'same ID retry does not duplicate');
 await assert.rejects(rpc('apply',{...command,fields:{...fields,notes:'different'}}),e=>e.code==='23505');
 await owner();assert.equal((await db.query('select count(*)::int n from private.qualification_submissions')).rows[0].n,0,'management operations require no approval queue');
 assert.equal((await db.query('select count(*)::int n from private.qualification_management_operations')).rows[0].n,1);
 const beforePhotos=await row();await actor(admin);
 await assert.rejects(rpc('apply',{request_id:id(24),target_id:target,operation:'photos',expected_snapshot:beforePhotos,fields:{photo_paths:['unapproved.jpg']}}),e=>e.code==='22023');
 await assert.rejects(rpc('apply',{request_id:id(24),target_id:target,operation:'photos',expected_snapshot:beforePhotos,fields:{photo_paths:[front,front]}}),e=>e.code==='22023');
 const reordered=await rpc('apply',{request_id:id(24),target_id:target,operation:'photos',expected_snapshot:beforePhotos,fields:{photo_paths:[back,front]}});
 assert.equal(reordered.after.attachment_path,back);assert.equal(reordered.after.attachment_back_path,front);
 assert.equal(reordered.after.certificate_number,'updated');
 const photosRemoved=await rpc('apply',{request_id:id(25),target_id:target,operation:'photos',expected_snapshot:reordered.after,fields:{photo_paths:[]}});
 assert.equal(photosRemoved.after.attachment_path,null);assert.deepEqual(photosRemoved.after.attachment_extra_paths,[]);
 const updated=await row();await actor(manager);
 const deleted=await rpc('apply',{request_id:id(21),target_id:target,operation:'delete',expected_snapshot:updated,fields:null});
 assert.equal(deleted.status,'applied');assert.equal(deleted.after,null);assert.equal(await row(),undefined);
 assert.equal((await db.query("select count(*)::int n from private.worker_qualification_history where source_id=$1 and operation='delete'",[target])).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,2);
 assert.ok((await db.query('select count(*)::int n from private.qualification_photo_history where paths @> array[$1::text]',[front])).rows[0].n>0);
 await actor(manager);const created=await rpc('apply',{request_id:id(22),target_id:id(30),operation:'create',worker_id:worker,qualification_master_id:master,expected_snapshot:null,fields});
 assert.equal(created.after.worker_id,worker);assert.equal(created.after.qualification_master_id,master);
 await owner();await db.query('update member_feature_permissions set can_manage_people=false where user_id=$1',[manager]);
 await actor(manager);await assert.rejects(rpc('apply',{request_id:id(23),target_id:id(30),operation:'delete',expected_snapshot:created.after,fields:null}),e=>e.code==='42501');
 await owner();await db.query('update member_feature_permissions set can_manage_people=true where user_id=$1',[manager]);
 // Existing personal photo requests still use the existing queue and approval.
 await actor(user);await personal('prepare_photos',{request_id:id(40),target_id:id(30),photo_slots:[]});await personal('submit',{id:id(40)});
 await actor(admin);await personal('approve',{id:id(40)});
 // Own first registration INSERT remains allowed; restrictive role applies only UPDATE/DELETE.
 await actor(user);await db.query('insert into worker_qualifications(id,company_id,worker_id,qualification_master_id) values($1,$2,$3,$4)',[id(31),company,worker,master]);
 await owner();assert.equal((await db.query("select md5(prosrc) m from pg_proc where oid='private.personal_qualification_submission(text,jsonb)'::regprocedure")).rows[0].m,personalBefore,'personal RPC source unchanged');
 await assert.rejects(db.exec("delete from private.qualification_management_operations"),e=>e.code==='42501');
 await db.exec('update private.qualification_management_state set enabled=false');
 await actor(admin);assert.equal((await rpc('get',{request_id:id(20)})).status,'applied','OFF retains committed outcome');
 await assert.rejects(rpc('apply',command),e=>e.code==='55000');
 await owner();await assert.rejects(db.exec(sql),e=>e.code==='42P07');await db.exec('rollback');
 console.log(`PASS direct qualification management (${native?'native PostgreSQL17':'PGlite'}): create/update/delete without independent approval; live role/company/snapshot/request boundaries, unchanged personal photos, immutable audit and retained official history/photos`);
}finally{await close();}
