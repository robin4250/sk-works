import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {randomUUID,randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
const here=path.dirname(fileURLToPath(import.meta.url));
const capture=JSON.parse(fs.readFileSync(path.join(here,'onboarding_storage_catalog.json'),'utf8'));
const status=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const origin=status.API_URL??status.api_url,dbUrl=status.DB_URL??status.db_url;
for(const value of [origin,dbUrl])assert.equal(new URL(value).hostname,'127.0.0.1','Local fixture only');
const anon=status.ANON_KEY??status.anon_key,service=status.SERVICE_ROLE_KEY??status.service_role_key;
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href);const Client=pg.Client??pg.default.Client;const db=new Client({connectionString:dbUrl});await db.connect();
async function request(route,{token=anon,method='POST',json={}}={}){return fetch(origin+route,{method,headers:{apikey:anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(json),signal:AbortSignal.timeout(10000)});}
async function user(label){const email=`${label}-${randomUUID()}@fixture.invalid`,password=randomBytes(24).toString('hex');let r=await request('/auth/v1/admin/users',{token:service,json:{email,password,email_confirm:true}});assert.equal(r.status,200);const u=await r.json();r=await request('/auth/v1/token?grant_type=password',{json:{email,password}});assert.equal(r.status,200);return{id:u.id,token:(await r.json()).access_token};}
const signature='public.save_employee_onboarding_profile(text,text,text,text,text,text,text,text,text,text)';
const original=capture.rpcs.find(f=>f.proname==='save_employee_onboarding_profile').definition;
const meta=async()=>(await db.query(`select oid,prosrc,proacl::text acl,proconfig,prosecdef from pg_proc where oid='${signature}'::regprocedure`)).rows[0];
let checks=0;
try{
 assert.equal((await db.query("select to_regclass('public.employee_registration_invites') is null empty")).rows[0].empty,true);
 const legacy=await user('legacy'),fresh=await user('fresh'),owner=await user('owner'),company=randomUUID();
 await db.query(`create schema private;create table private.account_deletion_access_restrictions(user_id uuid);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid,name text,phone_e164 text,status text,created_at timestamptz default now(),expires_at timestamptz default now()+interval '1 day',password_changed_at timestamptz,identity_verified_at timestamptz,address text,blood_type text,family_composition text,emergency_relation text,emergency_name text,emergency_phone text,emergency_address text,portrait_path text,my_number_front_path text,my_number_back_path text,submitted_at timestamptz);
 create table private.fixture_notifications(id uuid default gen_random_uuid(),company_id uuid,recipient uuid,kind text,action text,target uuid);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$insert into private.fixture_notifications(company_id,recipient,kind,action,target) values($1,$2,$3,$6,$7) returning id$$;
 grant usage on schema private to authenticated;
 revoke all on public.employee_registration_invites from public,anon,authenticated;
 alter table public.employee_registration_invites enable row level security;`);
 for(const f of capture.functions)await db.query(f.definition);
 for(const f of capture.rpcs){await db.query(f.definition);await db.query(`revoke execute on function public.${f.proname}(${f.args}) from public,anon;grant execute on function public.${f.proname}(${f.args}) to authenticated`);}
 await db.query(`grant execute on function ${signature} to service_role`);
 await db.query("insert into public.company_members values($1,$2,'owner')",[company,owner.id]);
 for(const [subject,hasPhotos]of[[legacy,true],[fresh,false]])await db.query("insert into public.employee_registration_invites(id,company_id,auth_user_id,status,password_changed_at,portrait_path,my_number_front_path,my_number_back_path) values($1,$2,$3,'profile_pending',now(),$4,$5,$6)",[randomUUID(),company,subject.id,hasPhotos?'fixture/legacy/portrait.png':null,hasPhotos?'fixture/legacy/front.png':null,hasPhotos?'fixture/legacy/back.png':null]);
 const beforeMeta=await meta(),members=(await db.query('select * from public.company_members')).rows,backups=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i order by id')).rows.map(x=>x.row);
 await db.query(fs.readFileSync(path.join(here,'onboarding_photo_retention.sql.review-only'),'utf8'));
 const afterMeta=await meta();assert.equal(afterMeta.oid,beforeMeta.oid);assert.equal(afterMeta.acl,beforeMeta.acl);assert.equal(afterMeta.prosrc,beforeMeta.prosrc.replace('      portrait_path = null,\n      my_number_front_path = null,\n      my_number_back_path = null,\n',''));
 await db.query(`create function public.fixture_retention_hook_seen() returns boolean language sql as $$select current_setting('sko.account_access_hook_ran',true)='true'$$;alter role authenticator set pgrst.db_pre_request='private.check_account_access';notify pgrst,'reload config';notify pgrst,'reload schema';`);
 let seen=false;for(let i=0;i<30;i++){const r=await request('/rest/v1/rpc/fixture_retention_hook_seen',{token:legacy.token});if(r.status===200&&(await r.json())===true){seen=true;break;}await new Promise(resolve=>setTimeout(resolve,200));}assert.equal(seen,true,'Actual existing account pre-hook must run');
 const rpc=(name,subject,json={})=>request('/rest/v1/rpc/'+name,{token:subject?.token??anon,json});
 const denied=async response=>{assert.ok([400,401,403,404].includes(response.status),'Actual authorization denial');await response.arrayBuffer();checks++;};
 const payload={p_address:'fixture address',p_blood_type:'unknown',p_family_composition:'fixture household',p_emergency_relation:'fixture',p_emergency_name:'fixture contact',p_emergency_phone:'fixture-only',p_emergency_address:'fixture address',p_portrait_path:null,p_my_number_front_path:null,p_my_number_back_path:null};
 for(const [subject,hasImages]of[[legacy,true],[fresh,false]]){
  const before=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i where auth_user_id=$1',[subject.id])).rows[0].row;
  let r=await rpc('employee_onboarding_photo_capability',subject);assert.equal(r.status,200);const capability=await r.json();assert.deepEqual(capability,{has_existing_images:hasImages,photo_upload_allowed:false});assert.ok(Object.values(capability).every(x=>typeof x==='boolean'));checks++;
  assert.deepEqual((await db.query('select to_jsonb(i) row from public.employee_registration_invites i where auth_user_id=$1',[subject.id])).rows[0].row,before,'Capability is read-only');
  r=await rpc('save_employee_onboarding_profile',subject,payload);assert.equal(r.status,204);const after=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i where auth_user_id=$1',[subject.id])).rows[0].row;
  for(const column of ['portrait_path','my_number_front_path','my_number_back_path'])assert.equal(after[column],before[column]);assert.equal(after.status,'approval_pending');checks++;
 }
 await denied(await rpc('employee_onboarding_photo_capability',null));await denied(await rpc('employee_onboarding_photo_capability',owner));
 await denied(await rpc('employee_onboarding_photo_capability',legacy,{p_subject:owner.id}));
 await denied(await rpc('read_employee_onboarding_photo_capability',legacy));
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[legacy.id]);await denied(await rpc('employee_onboarding_photo_capability',legacy));await db.query('delete from private.account_deletion_access_restrictions');
 await denied(await rpc('save_employee_onboarding_profile',legacy,{...payload,p_portrait_path:'fixture/new.png'}));
 const acl=(await db.query("select has_column_privilege('authenticated','public.employee_registration_invites','portrait_path','select') direct_select,has_function_privilege('anon','private.read_employee_onboarding_photo_capability()','execute') anon_execute,has_function_privilege('service_role','public.employee_onboarding_photo_capability()','execute') service_execute")).rows[0];assert.deepEqual(acl,{direct_select:false,anon_execute:false,service_execute:false});
 const columns=['status','address','blood_type','family_composition','emergency_relation','emergency_name','emergency_phone','emergency_address','portrait_path','my_number_front_path','my_number_back_path','submitted_at'];
 for(const row of backups)await db.query(`update public.employee_registration_invites set ${columns.map((c,i)=>c+'=$'+(i+1)).join(',')} where id=$${columns.length+1}`,[...columns.map(c=>row[c]),row.id]);
 await db.query('drop function public.employee_onboarding_photo_capability();drop function private.read_employee_onboarding_photo_capability()');await db.query(original);
 assert.deepEqual(await meta(),beforeMeta);assert.deepEqual((await db.query('select * from public.company_members')).rows,members);assert.deepEqual((await db.query('select to_jsonb(i) row from public.employee_registration_invites i order by id')).rows.map(x=>x.row),backups);
 const normal=await rpc('employee_onboarding_state',owner);assert.equal(normal.status,200);assert.equal(await normal.json(),null);checks++;
 assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[owner.id])).rows[0].n,1);
 console.log(`PASS ${checks} candidate-only actual GoTrue/Data-API checks; legacy three paths/new NULL/read-only boolean capability/account boundary/signature OID ACL/company owner identity/source restore preserved. No Storage or production/OAuth-provider equivalence claim.`);
}catch(e){console.error('Candidate HTTP fixture failed:',e.code??'',String(e.message).split('\n')[0]);process.exitCode=1;}finally{await db.end();}
