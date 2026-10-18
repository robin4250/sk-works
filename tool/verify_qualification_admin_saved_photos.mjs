// Disposable synthetic PGlite only. No Supabase, JWT server, cron or real files.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
const candidate=await read('docs/candidates/qualification_admin_saved_photos_20261019.sql.review-only');
for(const prepared of [false,true]) {
 const db=new PGlite();
 try {
 for(const p of ['tool/fixtures/qualification_photo_submission/schema.sql','tool/fixtures/qualification_photo_submission/live_functions.sql','supabase/migrations/20261010222157_add_qualification_certificate_extra_photos.sql','supabase/migrations/20261010222753_protect_qualification_photo_snapshots.sql','supabase/migrations/20261010233011_personal_qualification_photo_submission.sql']) await db.exec(await read(p));
 await db.exec(`alter table workers add column status text default 'active';
 create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('test.active',true),'true')='true'$$;
 create function public.account_server_access_allowed(uuid) returns boolean language sql stable as $$select coalesce(current_setting('test.requester_active',true),'true')='true'$$;
 create function private.has_company_feature(c uuid,f text) returns boolean language sql stable security definer as $$select coalesce(current_setting('test.manage_people',true),'true')='true' and exists(select 1 from public.company_members where company_id=c and user_id=auth.uid() and role in ('owner','admin'))$$;
 create policy fixture_admin_read on worker_qualifications for select to authenticated using(private.has_company_feature(company_id,'can_manage_people'));
 create policy fixture_admin_update on worker_qualifications for update to authenticated using(private.has_company_feature(company_id,'can_manage_people')) with check(private.has_company_feature(company_id,'can_manage_people'));
 grant execute on function private.personal_qualification_submission(text,jsonb) to authenticated;
 grant select on public.company_members to authenticated;`);
 if(prepared) {
  // Exact capability-only delta from the saved prepared-upload migration.
  const patch=await read('supabase/migrations/20261011033318_qualification_prepared_photo_upload.sql');
  const anchor=patch.match(/body:=replace\(body,\$old\$([\s\S]*?)\$old\$,\$new\$([\s\S]*?)\$new\$\)/);
  assert.ok(anchor);
  await db.exec('create function private.qualification_photo_upload_capability() returns boolean language sql as $$select false$$');
  const body=(await db.query("select prosrc from pg_proc where oid='private.personal_qualification_photo_submission(text,jsonb)'::regprocedure")).rows[0].prosrc;
  assert.ok(body.includes(anchor[1]));
  await db.query('select 1');
  const quoted=body.replace(anchor[1],anchor[2]).replaceAll("'","''");
  await db.exec("create or replace function private.personal_qualification_photo_submission(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as '"+quoted+"'");
 }
 const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [company,admin,reviewer,user,worker,master,target,foreignCompany,foreignUser]=Array.from({length:9},(_,i)=>id(i+1));
 const front=`${company}/${worker}/${master}/legacy/front.jpg`,back=`${company}/${worker}/${master}/legacy/back.jpg`;
 await db.query('insert into companies values($1),($2)',[company,foreignCompany]);
 await db.query("insert into company_members values($1,$2,'admin'),($1,$3,'admin'),($1,$4,'member'),($5,$6,'admin')",[company,admin,reviewer,user,foreignCompany,foreignUser]);
 await db.query('insert into workers(id,company_id,user_id)values($1,$2,$3)',[worker,company,user]);
 await db.query("insert into qualification_master values($1,$2,'Synthetic qualification',false)",[master,company]);
 await db.query("insert into storage.objects(bucket_id,name)values('qualification-certificates',$1),('qualification-certificates',$2)",[front,back]);
 await db.query("insert into worker_qualifications(id,company_id,worker_id,qualification_master_id,certificate_number,issuer,notes,attachment_path,attachment_back_path)values($1,$2,$3,$4,'original','issuer','original notes',$5,$6)",[target,company,worker,master,front,back]);
 const beforeAccess=(await db.query("select prosrc from pg_proc where oid='private.qualification_submission_access(text,boolean)'::regprocedure")).rows[0].prosrc;
 const original=(await db.query("select pg_get_functiondef('private.personal_qualification_submission(text,jsonb)'::regprocedure) definition")).rows[0].definition;
 await db.exec("create or replace function private.personal_qualification_submission(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb language sql as 'select null::jsonb'");
 await assert.rejects(db.exec(candidate),e=>e.code==='55000');
 await db.exec('rollback');
 assert.equal((await db.query("select to_regclass('private.qualification_approved_write_permits') r")).rows[0].r,null);
 await db.exec(original);
 await db.exec(`set test.uid='${admin}'`);
 await assert.rejects(db.query("select private.personal_qualification_submission('admin_saved_photo_capability',$1::jsonb)",[JSON.stringify({company_id:company})]),'old API must not identify management capability');
 const personalCapabilityBefore=(await db.query("select private.personal_qualification_submission('photo_capability','{}') v")).rows[0].v;
 await db.exec(candidate);
 // Inspect the actually installed function: retry prepare must never acquire
 // its request-row lock after holding the shared qualification advisory lock.
 const adminBody=(await db.query("select prosrc from pg_proc where oid='private.admin_qualification_saved_photos(text,jsonb)'::regprocedure")).rows[0].prosrc;
 const prepareBody=adminBody.slice(adminBody.indexOf("if p_action='prepare_admin_saved_photos'"),adminBody.indexOf("\n select * into req from private.qualification_submissions where id=(p_data->>'id')"));
 const requestReads=[...prepareBody.matchAll(/select \* into req from private\.qualification_submissions where id=request_id(?: for update)?;/g)];
 assert.equal(requestReads.length,2,'prepare must lock request first, then recheck without locking after qualification');
 assert.ok(requestReads[0][0].endsWith(' for update;'),'first request read locks before advisory');
 assert.ok(!requestReads[1][0].endsWith(' for update;'),'late request recheck cannot wait on an approver request lock');
 const advisory=prepareBody.indexOf('perform pg_advisory_xact_lock(');
 const qualification=prepareBody.indexOf('for update of q;');
 assert.ok(requestReads[0].index<advisory && advisory<qualification && qualification<requestReads[1].index,'request → advisory → qualification → nonlocking retry recheck');
 const remainingBody=adminBody.slice(adminBody.indexOf("\n select * into req from private.qualification_submissions where id=(p_data->>'id')"));
 assert.ok(remainingBody.indexOf('for update;')<remainingBody.indexOf('perform pg_advisory_xact_lock('),'submit/approve keep request-first order');
 assert.equal((await db.query("select prosrc from pg_proc where oid='private.qualification_submission_access(text,boolean)'::regprocedure")).rows[0].prosrc,beforeAccess);
 const actor=async uid=>db.exec(`reset role;set test.uid='${uid}';set role authenticated`);
 const owner=()=>db.exec('reset role');
 const rpc=async(action,data={})=>(await db.query('select private.personal_qualification_submission($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;
 const getrow=async()=>{await owner();return (await db.query('select * from worker_qualifications where id=$1',[target])).rows[0];};
 const prepare=(request,paths)=>rpc('prepare_admin_saved_photos',{company_id:company,target_id:target,request_id:id(request),photo_slots:paths.map(existing_path=>({existing_path}))});
 await actor(admin);
 assert.deepEqual(await rpc('photo_capability'),personalCapabilityBefore,'personal capability response is byte-semantic unchanged');
 const capabilityData={company_id:company};
 const expectedCapability={version:1,contract:'qualification_admin_saved_photos',company_id:company,actor_id:admin,
 photo_submission_available:true,photo_upload_allowed:false,max_photos:20,self_approval_allowed:false};
 assert.deepEqual(await rpc('admin_saved_photo_capability',capabilityData),expectedCapability);
 // Consumer contract oracle only; production UI is not enabled by this fixture.
 const allowsManagement=raw=>raw!==null && typeof raw==='object' && !Array.isArray(raw)
  && Object.keys(raw).length===8 && raw.version===1 && raw.contract==='qualification_admin_saved_photos'
  && raw.company_id===company && raw.actor_id===admin && raw.photo_submission_available===true
  && raw.photo_upload_allowed===false && raw.max_photos===20 && raw.self_approval_allowed===false;
 assert.equal(allowsManagement(personalCapabilityBefore),false);
 assert.equal(allowsManagement(expectedCapability),true);
 for(const bad of [null,{}, {...expectedCapability,version:0},{...expectedCapability,version:2},
 {...expectedCapability,contract:'unknown'}, {...expectedCapability,actor_id:user},
 {...expectedCapability,company_id:foreignCompany},{...expectedCapability,photo_submission_available:false},
 {...expectedCapability,photo_upload_allowed:true},{...expectedCapability,self_approval_allowed:true},
 {...expectedCapability,max_photos:21},{...expectedCapability,unexpected:true}]) assert.equal(allowsManagement(bad),false);

 await db.exec("set test.manage_people='false'");
 assert.deepEqual(await rpc('admin_saved_photo_capability',capabilityData),{...expectedCapability,photo_submission_available:false});
 await db.exec("set test.manage_people='true'");
 await actor(user);assert.equal((await rpc('admin_saved_photo_capability',capabilityData)).photo_submission_available,false);
 await actor(foreignUser);assert.equal((await rpc('admin_saved_photo_capability',capabilityData)).photo_submission_available,false);
 await actor(admin);assert.equal((await rpc('admin_saved_photo_capability',{company_id:foreignCompany})).photo_submission_available,false);
 await assert.rejects(rpc('admin_saved_photo_capability',{}),e=>e.code==='22023');
 await assert.rejects(rpc('admin_saved_photo_capability',{company_id:'wrong'}),e=>e.code==='22P02');
 await db.exec("set test.active='false'");await assert.rejects(rpc('admin_saved_photo_capability',capabilityData),e=>e.code==='42501');
 await db.exec("set test.active='true'");
 // This snapshot is not an authorization token: changed current permission still denies prepare.
 await db.exec("set test.manage_people='false'");await assert.rejects(prepare(19,[front]),e=>e.code==='42501');
 await db.exec("set test.manage_people='true'");
 const initial=await getrow(); await actor(admin);
 const draft=await prepare(20,[back,front]);
 assert.equal(draft.requested_by,admin);assert.deepEqual(draft.upload_paths,[]);
 assert.deepEqual(await prepare(20,[back,front]),draft);
 // Unknown account helper fails closed for every new management entry, not only capability.
 await owner();
 const officialBeforeNull=(await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v;
 const requestsBeforeNull=(await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows;
 const accountDefinition=(await db.query("select pg_get_functiondef('private.account_access_allowed()'::regprocedure) d")).rows[0].d;
 await db.exec('create or replace function private.account_access_allowed() returns boolean language sql stable as $$select null::boolean$$');
 await actor(admin);
 await assert.rejects(rpc('admin_saved_photo_capability',capabilityData),e=>e.code==='42501');
 await assert.rejects(prepare(18,[front]),e=>e.code==='42501');
 for(const action of ['get_photos','submit','cancel_photos','approve','reject']) {
  await assert.rejects(rpc(action,{id:id(20),reason:'synthetic rejection'}),e=>e.code==='42501');
 }
 await owner();
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,officialBeforeNull);
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,requestsBeforeNull);
 await db.exec(accountDefinition);
 await actor(admin);
 assert.deepEqual(await rpc('admin_saved_photo_capability',capabilityData),expectedCapability);

 await assert.rejects(prepare(20,[front,back]),e=>e.code==='23505');
 assert.deepEqual(await getrow(),initial);
 await actor(admin);assert.equal((await rpc('submit',{id:id(20)})).status,'pending');
 assert.equal((await prepare(20,[back,front])).status,'pending');
 await assert.rejects(rpc('approve',{id:id(20)}),e=>e.code==='42501');
 await assert.rejects(db.query("update worker_qualifications set notes='direct edit' where id=$1",[target]),e=>e.code==='42501');
 await assert.rejects(db.query('insert into private.qualification_approved_write_permits select 1,$1,$2,$3,\'{}\',\'{}\'',[target,admin,id(20)]),e=>e.code==='42501');
 await assert.rejects(rpc('prepare_admin_saved_photos',{company_id:company,target_id:target,request_id:id(21),photo_slots:[{extension:'jpg'}]}));
 await actor(foreignUser);await assert.rejects(prepare(22,[front]),e=>e.code==='42501');
 await actor(reviewer);assert.equal((await rpc('approve',{id:id(20)})).status,'approved');
 let saved=await getrow();assert.equal(saved.attachment_path,back);assert.equal(saved.attachment_back_path,front);assert.equal(saved.notes,initial.notes);
 assert.equal((await db.query('select count(*)::int n from private.qualification_approved_write_permits')).rows[0].n,0);
 assert.ok((await db.query('select count(*)::int n from private.qualification_photo_history')).rows[0].n>=3);
 await actor(admin);assert.equal((await prepare(20,[back,front])).status,'approved');
 assert.deepEqual(await getrow(),saved);
 // Existing personal photo contract still goes through the same normal approve.
 await actor(user);await rpc('prepare_photos',{request_id:id(23),target_id:target,photo_slots:[{existing_path:front}]});
 await rpc('submit',{id:id(23)});await actor(reviewer);await rpc('approve',{id:id(23)});
 assert.equal((await getrow()).attachment_path,front);
 // Existing single-photo metadata prepare/submit/approve must retain compatibility.
 await actor(user);const legacy=await rpc('prepare',{worker_id:worker,qualification_master_id:master,target_id:target,certificate_number:'new number',issuer:'new issuer',notes:'approved metadata'});
 await rpc('submit',{id:legacy.id});await actor(reviewer);await rpc('approve',{id:legacy.id});
 saved=await getrow();assert.equal(saved.certificate_number,'new number');assert.equal(saved.notes,'approved metadata');
 // Old snapshot CAS: an independent legacy approval supersedes an admin draft.
 await actor(admin);await prepare(24,[]);await rpc('submit',{id:id(24)});
 await actor(user);const newer=await rpc('prepare',{worker_id:worker,qualification_master_id:master,target_id:target,certificate_number:'newer',notes:'newer'});
 await rpc('submit',{id:newer.id});await actor(reviewer);await rpc('approve',{id:newer.id});
 await assert.rejects(rpc('approve',{id:id(24)}),e=>e.code==='40001');
 // Current requester authority is checked again after submit.
 await actor(admin);await prepare(25,[]);await rpc('submit',{id:id(25)});
 await owner();await db.query("update company_members set role='member' where company_id=$1 and user_id=$2",[company,admin]);
 await actor(reviewer);await assert.rejects(rpc('approve',{id:id(25)}),e=>e.code==='42501');
 await owner();await db.query("update company_members set role='admin' where company_id=$1 and user_id=$2",[company,admin]);
 await actor(reviewer);await db.exec("set test.requester_active='false'");await assert.rejects(rpc('approve',{id:id(25)}),e=>e.code==='42501');await db.exec("set test.requester_active='true'");
 assert.equal((await rpc('approve',{id:id(25)})).status,'approved');
 saved=await getrow();assert.equal(saved.attachment_path,null);assert.deepEqual(saved.attachment_extra_paths,[]);
 // Exact target worker/master current-company bindings are rechecked.
 await actor(admin);await prepare(26,[]);await rpc('submit',{id:id(26)});
 await owner();await db.query('update qualification_master set company_id=$1 where id=$2',[foreignCompany,master]);
 await actor(reviewer);await assert.rejects(rpc('approve',{id:id(26)}),e=>e.code==='40001');
 await owner();await db.query('update qualification_master set company_id=$1 where id=$2',[company,master]);
 await db.query('update workers set company_id=$1 where id=$2',[foreignCompany,worker]);
 await actor(reviewer);await assert.rejects(rpc('approve',{id:id(26)}),e=>e.code==='40001');
 await owner();await db.query('update workers set company_id=$1 where id=$2',[company,worker]);
 await db.query("update company_members set role='member' where company_id=$1 and user_id=$2",[company,reviewer]);
 await actor(reviewer);await assert.rejects(rpc('approve',{id:id(26)}),e=>e.code==='42501');
 await owner();await db.query("update company_members set role='admin' where company_id=$1 and user_id=$2",[company,reviewer]);
 await actor(reviewer);await rpc('approve',{id:id(26)});
 // Capability OFF refuses all three management actions, even with an admin role.
 await actor(admin);await db.exec("set test.manage_people='false'");await assert.rejects(prepare(27,[]),e=>e.code==='42501');
 await db.exec("set test.manage_people='true'");await prepare(27,[]);
 await db.exec("set test.manage_people='false'");await assert.rejects(rpc('submit',{id:id(27)}),e=>e.code==='42501');
 await db.exec("set test.manage_people='true'");await rpc('submit',{id:id(27)});
 await actor(reviewer);await db.exec("set test.manage_people='false'");await assert.rejects(rpc('approve',{id:id(27)}),e=>e.code==='42501');
 await db.exec("set test.manage_people='true'");
 await owner();await db.query("update workers set status='inactive' where id=$1",[worker]);
 await actor(reviewer);await assert.rejects(rpc('approve',{id:id(27)}),e=>e.code==='40001');
 await owner();await db.query("update workers set status='active' where id=$1",[worker]);
 await actor(reviewer);await rpc('approve',{id:id(27)});
 // First INSERT remains unaffected, existing direct metadata edits remain denied.
 await owner();await db.query('insert into worker_qualifications(id,company_id,worker_id,qualification_master_id)values($1,$2,$3,$4)',[id(30),company,worker,master]);
 await actor(reviewer);await assert.rejects(db.query("update worker_qualifications set issuer='bypass' where id=$1",[target]),e=>e.code==='42501');
 await db.exec("set test.active='false'");await assert.rejects(prepare(31,[]),e=>e.code==='42501');
 await owner();assert.equal((await db.query('select count(*)::int n from private.qualification_approved_write_permits')).rows[0].n,0);
 // Exact original source drift failed before candidate DDL, checked above.
 console.log(`PASS qualification admin saved photos: ${prepared?'prepared capability delta':'base photo source'}; existing queue, initial INSERT, independent approve, legacy/photo compatibility, CAS, current authority, no upload, direct-write denial, history, request-first lock-order source contract, retry conflicts and separate management capability/personal response compatibility`);
 } finally {await db.close();}
}
