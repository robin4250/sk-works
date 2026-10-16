import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {randomBytes,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const here=path.dirname(fileURLToPath(import.meta.url));
const capture=JSON.parse(fs.readFileSync(path.join(here,'onboarding_storage_catalog.json'),'utf8'));
const status=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const origin=status.API_URL??status.api_url,dbUrl=status.DB_URL??status.db_url;
for(const value of [origin,dbUrl])assert.equal(new URL(value).hostname,'127.0.0.1','Private local fixture endpoints only');
const anon=status.ANON_KEY??status.anon_key,service=status.SERVICE_ROLE_KEY??status.service_role_key;assert.ok(typeof anon==='string'&&typeof service==='string');
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href);const Client=pg.Client??pg.default.Client;const db=new Client({connectionString:dbUrl});await db.connect();
let checks=0;
async function req(route,{token=anon,method='GET',json,body,headers={}}={}){return fetch(origin+route,{method,headers:{apikey:anon,Authorization:`Bearer ${token}`,...(json?{'Content-Type':'application/json'}:{}),...headers},body:json?JSON.stringify(json):body,signal:AbortSignal.timeout(10000)});}
async function user(label){const email=`${label}-${randomUUID()}@fixture.invalid`,password=randomBytes(24).toString('hex');let r=await req('/auth/v1/admin/users',{token:service,method:'POST',json:{email,password,email_confirm:true}});assert.equal(r.status,200);const u=await r.json();r=await req('/auth/v1/token?grant_type=password',{method:'POST',json:{email,password}});assert.equal(r.status,200);const session=await r.json();return{id:u.id,token:session.access_token,refresh:session.refresh_token};}
const company=randomUUID(),foreignCompany=randomUUID(),invite=randomUUID(),worker=randomUUID();
const bucket='employee-onboarding-documents';
const q=s=>"'"+s.replaceAll("'","''")+"'";
async function denied(response){assert.ok([400,401,403,404].includes(response.status),'Actual HTTP denial required');await response.arrayBuffer();checks++;}
async function allowed(response,bytes){assert.equal(response.status,200,'Actual HTTP normal access');if(bytes)assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);else await response.arrayBuffer();checks++;}
try{
 assert.equal((await db.query("select to_regclass('public.employee_registration_invites') is null as empty")).rows[0].empty,true,'Empty application fixture required');
 assert.equal((await db.query("select count(*)::int n from pg_policies where schemaname='storage' and tablename='objects'")).rows[0].n,0,'Fresh Storage fixture only');
 const users={};for(const label of ['self','owner','admin','approver','manager','viewer','foreign','unrelated'])users[label]=await user(label);
 await db.query(`create schema private;create type public.app_role as enum('owner','admin','manager','viewer','worker');
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table public.company_members(company_id uuid,user_id uuid,role public.app_role);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid,name text,phone_e164 text,status text,created_at timestamptz default now(),expires_at timestamptz default now()+interval '1 day',password_changed_at timestamptz,identity_verified_at timestamptz,address text,blood_type text,family_composition text,emergency_relation text,emergency_name text,emergency_phone text,emergency_address text,portrait_path text,my_number_front_path text,my_number_back_path text,submitted_at timestamptz);
 create table private.fixture_notifications(id uuid default gen_random_uuid(),company_id uuid,recipient uuid,kind text,action text,target uuid);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$insert into private.fixture_notifications(company_id,recipient,kind,action,target) values($1,$2,$3,$6,$7) returning id$$;
 grant usage on schema private to authenticated;`);
 for(const f of capture.functions)await db.query(f.definition);
 for(const f of capture.rpcs){await db.query(f.definition);await db.query(`revoke execute on function public.${f.proname}(${f.args}) from public,anon;grant execute on function public.${f.proname}(${f.args}) to authenticated`);}
 for(const fn of ['can_upload_onboarding_document()','can_review_employee_onboarding_user(uuid)'])await db.query(`revoke execute on function private.${fn} from public,anon;grant execute on function private.${fn} to authenticated`);
 // Other official-bucket branches must never be called for this bucket. No mock grants or allow-all replacements.
 for(const fn of ['license_document_upload_allowed','qualification_photo_draft_upload_allowed','worker_document_photo_upload_allowed'])await db.query(`create function private.${fn}(text) returns boolean language plpgsql as $$begin raise exception 'unrelated official bucket branch reached';end$$;revoke execute on function private.${fn}(text) from public,anon;grant execute on function private.${fn}(text) to authenticated`);
 for(const p of capture.policies){const roles=p.roles.slice(1,-1).split(',').join(',');await db.query(`create policy ${JSON.stringify(p.policyname)} on storage.objects as ${p.permissive} for ${p.cmd} to ${roles}${p.qual?' using ('+p.qual+')':''}${p.with_check?' with check ('+p.with_check+')':''}`);}
 for(const [name,role]of[['owner','owner'],['admin','admin'],['approver','worker'],['manager','manager'],['viewer','viewer']])await db.query('insert into public.company_members values($1,$2,$3::public.app_role)',[company,users[name].id,role]);
 await db.query("insert into public.company_members values($1,$2,'admin')",[foreignCompany,users.foreign.id]);
 await db.query('insert into public.company_approval_assignees values($1,$2)',[company,users.approver.id]);
 await db.query("insert into public.employee_registration_invites(id,company_id,worker_id,auth_user_id,name,phone_e164,status,password_changed_at) values($1,$2,$3,$4,'synthetic applicant','fixture-only','profile_pending',now())",[invite,company,worker,users.self.id]);
 const memberships=(await db.query('select company_id,user_id,role::text role from public.company_members order by user_id')).rows;
 const inviteBackup=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i')).rows[0].row;
 const aclBefore=(await db.query("select oid::regclass::text name,relowner,relacl::text acl from pg_class where oid in('auth.users'::regclass,'auth.sessions'::regclass) order by oid")).rows;
 await db.query(`create function public.fixture_onboarding_hook_seen() returns boolean language sql as $$select current_setting('sko.account_access_hook_ran',true)='true'$$;grant execute on function public.fixture_onboarding_hook_seen() to authenticated;
 alter role authenticator set pgrst.db_pre_request='private.check_account_access';notify pgrst,'reload config';notify pgrst,'reload schema';`);
 let hookSeen=false;for(let attempt=0;attempt<30;attempt++){const r=await req('/rest/v1/rpc/fixture_onboarding_hook_seen',{token:users.self.token,method:'POST',json:{}});if(r.status===200&&(await r.json())===true){hookSeen=true;break;}await new Promise(resolve=>setTimeout(resolve,200));}assert.equal(hookSeen,true,'Actual copied Data API pre-request hook must run');checks++;
 const rpc=(name,token,json={})=>req('/rest/v1/rpc/'+name,{token,method:'POST',json});
 let r=await rpc('employee_onboarding_state',users.self.token);assert.equal(r.status,200);assert.equal((await r.json()).status,'profile_pending');checks++;
 r=await rpc('employee_onboarding_state',users.owner.token);assert.equal(r.status,200);assert.equal(await r.json(),null);checks++;
 await denied(await rpc('employee_onboarding_state',anon));
 await denied(await rpc('can_upload_onboarding_document',users.self.token));
 await denied(await rpc('can_review_employee_onboarding_user',users.owner.token,{p_subject_user_id:users.self.id}));
 const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6oAAAAABJRU5ErkJggg==','base64');
 const object=users.self.id+'/legacy-fixture.png';
 r=await req('/storage/v1/bucket',{token:service,method:'POST',json:{id:bucket,name:bucket,public:false}});assert.equal(r.status,200);
 r=await req('/storage/v1/object/'+bucket+'/'+object,{token:service,method:'POST',body:bytes,headers:{'Content-Type':'image/png','Cache-Control':'max-age=0'}});assert.equal(r.status,200);
 const download=token=>req('/storage/v1/object/authenticated/'+bucket+'/'+object,{token});
 for(const name of ['self','owner','admin','approver'])await allowed(await download(users[name].token),bytes);
 for(const name of ['manager','viewer','foreign','unrelated'])await denied(await download(users[name].token));await denied(await download(anon));
 assert.equal((await db.query('select count(*)::int n from public.company_members where user_id=$1',[users.self.id])).rows[0].n,0,'Applicant bootstrap has no company membership');
 // Actual current pause: even valid invited users cannot create new onboarding images.
 for(const state of ['invited','password_changed','profile_pending','approval_pending','approved','cancelled']){
  await db.query('update public.employee_registration_invites set status=$1 where id=$2',[state,invite]);
  await denied(await req('/storage/v1/object/'+bucket+'/'+users.self.id+'/new-'+state+'.png',{token:users.self.token,method:'POST',body:bytes,headers:{'Content-Type':'image/png'}}));
 }
 await db.query("update public.employee_registration_invites set status='profile_pending' where id=$1",[invite]);
 await denied(await req('/storage/v1/object/'+bucket+'/'+object,{token:users.self.token,method:'PUT',body:bytes,headers:{'Content-Type':'image/png'}}));
 const payload={p_address:'synthetic address',p_blood_type:'unknown',p_family_composition:'synthetic household',p_emergency_relation:'fixture',p_emergency_name:'synthetic contact',p_emergency_phone:'fixture-only',p_emergency_address:'synthetic address',p_portrait_path:null,p_my_number_front_path:null,p_my_number_back_path:null};
 const beforePause=(await db.query('select to_jsonb(i) row from public.employee_registration_invites i')).rows;
 await denied(await rpc('save_employee_onboarding_profile',users.self.token,{...payload,p_portrait_path:object}));
 assert.deepEqual((await db.query('select to_jsonb(i) row from public.employee_registration_invites i')).rows,beforePause);
 r=await rpc('save_employee_onboarding_profile',users.self.token,payload);assert.equal(r.status,204,'Actual backend no-photo initial beta route must remain usable');checks++;
 assert.equal((await db.query('select status from public.employee_registration_invites where id=$1',[invite])).rows[0].status,'approval_pending');
 assert.deepEqual((await db.query('select recipient from private.fixture_notifications order by recipient')).rows.map(x=>x.recipient),[users.owner.id,users.admin.id,users.approver.id].sort());
 console.log('VERIFIED current backend photo-NULL submission succeeds for pre-membership applicant; photo uploads/nonempty paths remain intentionally paused. Main photo-required UI is a separate contract mismatch, not all registration paths blocked.');
 // Current pre-request hook, not merely the function body, blocks restricted Data API callers.
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.self.id]);await denied(await download(users.self.token));await denied(await rpc('save_employee_onboarding_profile',users.self.token,payload));
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.self.id]);await allowed(await download(users.self.token),bytes);
 r=await req('/storage/v1/object/sign/'+bucket+'/'+object,{token:users.approver.token,method:'POST',json:{expiresIn:2}});assert.equal(r.status,200);const relative=(await r.json()).signedURL;assert.ok(typeof relative==='string'&&relative.startsWith('/object/sign/'));const signed=new URL(origin+'/storage/v1'+relative);assert.equal(signed.origin,new URL(origin).origin);
 await db.query('delete from public.company_approval_assignees where user_id=$1',[users.approver.id]);await denied(await download(users.approver.token));
 r=await fetch(signed,{cache:'no-store',signal:AbortSignal.timeout(10000)});await allowed(r,bytes);console.log('OBSERVED prior onboarding signed URL still usable before TTL after reviewer permission removal');
 await new Promise(resolve=>setTimeout(resolve,5000));await denied(await fetch(signed,{cache:'no-store',signal:AbortSignal.timeout(10000)}));
 await db.query('insert into public.company_approval_assignees values($1,$2)',[company,users.approver.id]);await allowed(await download(users.approver.token),bytes);
 const claims=JSON.parse(Buffer.from(users.self.token.split('.')[1],'base64url').toString());r=await req('/auth/v1/logout?scope=local',{token:users.self.token,method:'POST'});assert.ok([200,204].includes(r.status));
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1',[claims.session_id])).rows[0].n,0);
 r=await download(users.self.token);assert.equal(r.status,200,'Baseline observation: old unexpired JWT retains Storage access');await r.arrayBuffer();checks++;
 console.log('OBSERVED baseline onboarding read still accepts unexpired old JWT after actual logout/session removal; no session guard applied');
 await db.query('update public.employee_registration_invites set (status,address,blood_type,family_composition,emergency_relation,emergency_name,emergency_phone,emergency_address,portrait_path,my_number_front_path,my_number_back_path,submitted_at)=($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) where id=$13',[inviteBackup.status,inviteBackup.address,inviteBackup.blood_type,inviteBackup.family_composition,inviteBackup.emergency_relation,inviteBackup.emergency_name,inviteBackup.emergency_phone,inviteBackup.emergency_address,inviteBackup.portrait_path,inviteBackup.my_number_front_path,inviteBackup.my_number_back_path,inviteBackup.submitted_at,invite]);
 assert.deepEqual((await db.query('select to_jsonb(i) row from public.employee_registration_invites i')).rows[0].row,inviteBackup);
 assert.deepEqual((await db.query('select company_id,user_id,role::text role from public.company_members order by user_id')).rows,memberships);
 assert.deepEqual((await db.query("select oid::regclass::text name,relowner,relacl::text acl from pg_class where oid in('auth.users'::regclass,'auth.sessions'::regclass) order by oid")).rows,aclBefore);
 for(const name of ['owner','admin','approver'])await allowed(await download(users[name].token),bytes);
 assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[users.owner.id])).rows[0].n,1);
 console.log(`PASS ${checks} actual local onboarding Auth/Storage/Data-API checks; memberships/roles/owner ID/legacy bytes/ACL restored. No product RLS/auth/source changes; no production or CDN/provider equivalence claim.`);
}catch(e){console.error('Fixture verification failed:',e.code??'',e.message);process.exitCode=1;}finally{await db.end();}
