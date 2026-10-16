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
 await db.query(fs.readFileSync(path.join(here,'onboarding_safe_save.sql.review-only'),'utf8'));
 await db.query(`create function public.fixture_retention_hook_seen() returns boolean language sql as $$select current_setting('sko.account_access_hook_ran',true)='true'$$;alter role authenticator set pgrst.db_pre_request='private.check_account_access';notify pgrst,'reload config';notify pgrst,'reload schema';`);
 let seen=false;for(let i=0;i<30;i++){const r=await request('/rest/v1/rpc/fixture_retention_hook_seen',{token:legacy.token});if(r.status===200&&(await r.json())===true){seen=true;break;}await new Promise(resolve=>setTimeout(resolve,200));}assert.equal(seen,true);
 const rpc=(name,subject,json={})=>request('/rest/v1/rpc/'+name,{token:subject?.token??anon,json});
 const payload={p_address:'fixture address',p_blood_type:'unknown',p_family_composition:'fixture household',p_emergency_relation:'fixture',p_emergency_name:'fixture contact',p_emergency_phone:'fixture-only',p_emergency_address:'fixture address'};
 const save=subject=>rpc('save_employee_onboarding_profile_without_photos',subject,payload);
 const snapshot=async()=>(await db.query("select jsonb_build_object('invites',(select jsonb_agg(to_jsonb(i) order by id) from public.employee_registration_invites i),'notifications',(select jsonb_agg(to_jsonb(n) order by id) from private.fixture_notifications n)) s")).rows[0].s;
 const invariant=async(uid,before)=>{const after=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i where auth_user_id=$1',[uid])).rows[0].row;for(const c of ['id','company_id','auth_user_id','portrait_path','my_number_front_path','my_number_back_path'])assert.equal(after[c],before[c]);assert.equal(after.status,'approval_pending');};
 for(const subject of [legacy,fresh]){const before=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i where auth_user_id=$1',[subject.id])).rows[0].row;const r=await save(subject);assert.equal(r.status,204);await invariant(subject.id,before);checks++;}
 // Capability observed first, then original destructive save restored before RPC dispatch.
 let r=await rpc('employee_onboarding_photo_capability',legacy);assert.equal(r.status,200);assert.equal((await r.json()).photo_upload_allowed,false);
 await db.query(original);const beforeFailure=await snapshot();r=await save(legacy);assert.equal(r.status,500);assert.equal((await r.json()).code,'55000');assert.deepEqual(await snapshot(),beforeFailure,'Failed assertion rolls back text/status/photos AND synthetic notification sink');checks++;
 r=await save(fresh);assert.equal(r.status,204);checks++;
 // Restore retained save without touching capability or dedicated API.
 const retention=fs.readFileSync(path.join(here,'onboarding_photo_retention.sql.review-only'),'utf8');await db.query(retention.replace(/create function private.read_employee_onboarding_photo_capability\(\)[\s\S]*?commit;/,'commit;'));
 // Real two-connection row-lock interleaving, not an in-process serialization claim.
 const locker=new Client({connectionString:dbUrl});await locker.connect();
 try{
  await locker.query('begin');await locker.query("update public.employee_registration_invites set portrait_path='fixture/locked/latest.png' where auth_user_id=$1",[legacy.id]);
  const pending=save(legacy);let blocked=false;
  for(let i=0;i<40;i++){if((await db.query("select exists(select 1 from pg_stat_activity where datname=current_database() and wait_event_type='Lock' and usename='authenticator') blocked")).rows[0].blocked){blocked=true;break;}await new Promise(resolve=>setTimeout(resolve,100));}
  assert.equal(blocked,true,'Actual Data API transaction must wait on locked invite');await locker.query('commit');r=await pending;assert.equal(r.status,204);assert.equal((await db.query('select portrait_path from public.employee_registration_invites where auth_user_id=$1',[legacy.id])).rows[0].portrait_path,'fixture/locked/latest.png');checks++;
 }finally{await locker.query('rollback');await locker.end();}
 for(const subject of [null,owner]){r=await save(subject);assert.ok([401,403].includes(r.status));checks++;}
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[legacy.id]);r=await save(legacy);assert.ok([401,403].includes(r.status));await db.query('delete from private.account_deletion_access_restrictions');checks++;
 r=await rpc('save_employee_onboarding_profile_without_photos',legacy,{...payload,p_subject:owner.id});assert.equal(r.status,404);checks++;
 r=await rpc('save_employee_onboarding_profile_without_photos',legacy,{...payload,p_address:null});assert.equal(r.status,400);checks++;
 r=await rpc('save_employee_onboarding_profile_without_photos',legacy,{...payload,p_portrait_path:'fixture/forbidden.png'});assert.equal(r.status,404);checks++;
 r=await rpc('save_employee_onboarding_profile_without_photos',legacy,payload);assert.equal(r.status,204);checks++;
 const safeSignature='(text,text,text,text,text,text,text)';
 await db.query('drop function public.save_employee_onboarding_profile_without_photos'+safeSignature+';drop function private.save_employee_onboarding_profile_without_photos'+safeSignature+";notify pgrst,'reload schema'");
 let missing=false;for(let i=0;i<30;i++){r=await save(legacy);if(r.status===404){missing=true;assert.equal((await r.json()).code,'PGRST202');break;}await new Promise(resolve=>setTimeout(resolve,100));}assert.equal(missing,true);checks++;
 const columns=['status','address','blood_type','family_composition','emergency_relation','emergency_name','emergency_phone','emergency_address','portrait_path','my_number_front_path','my_number_back_path','submitted_at'];
 for(const row of backups)await db.query(`update public.employee_registration_invites set ${columns.map((c,i)=>c+'=$'+(i+1)).join(',')} where id=$${columns.length+1}`,[...columns.map(c=>row[c]),row.id]);
 await db.query('truncate private.fixture_notifications;drop function public.employee_onboarding_photo_capability();drop function private.read_employee_onboarding_photo_capability()');await db.query(original);
 assert.deepEqual(await meta(),beforeMeta);assert.deepEqual((await db.query('select * from public.company_members')).rows,members);assert.deepEqual((await db.query('select to_jsonb(i) row from public.employee_registration_invites i order by id')).rows.map(x=>x.row),backups);
 assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[owner.id])).rows[0].n,1);checks++;
 console.log(`PASS ${checks} actual GoTrue/Data API dedicated omission-RPC checks: stale capability/old-save rollback, real row-lock race, notifications rollback, missing RPC safe error, legacy/fresh preservation and complete source/data/admin restoration. No production/Storage/OAuth-provider proof.`);
}catch(e){console.error('Safe-save HTTP fixture failed:',e.code??'',String(e.message).split('\n')[0],typeof e.actual==='number'?e.actual:'',typeof e.expected==='number'?e.expected:'',String(e.stack).split('\n').find(x=>x.includes('onboarding_safe_save_http.mjs:'))??'');process.exitCode=1;}finally{await db.end();}
