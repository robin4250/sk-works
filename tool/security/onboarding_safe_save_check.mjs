import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const capture=JSON.parse(fs.readFileSync(path.join(here,'onboarding_storage_catalog.json'),'utf8'));
const original=capture.rpcs.find(f=>f.proname==='save_employee_onboarding_profile').definition;
const candidate=fs.readFileSync(path.join(here,'onboarding_safe_save.sql.review-only'),'utf8');
let db;
if(process.argv[3]==='--pg17'){
 const url=new URL(process.env.SKO_ONBOARDING_RETAIN_FIXTURE_URL??'');assert.ok(url.hostname==='127.0.0.1'&&url.pathname==='/sko_onboarding_retain_fixture');
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new (mod.Client??mod.default.Client)({connectionString:url.href});await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private','auth') and c.relkind='r'")).rows[0].n,0);
}else{const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const legacy=id(1),fresh=id(2),owner=id(3),company=id(4);
const signature='public.save_employee_onboarding_profile(text,text,text,text,text,text,text,text,text,text)';
const params=['synthetic address','unknown','synthetic household','fixture','synthetic contact','fixture-only','synthetic address',null,null,null];
const save=()=>db.query('select public.save_employee_onboarding_profile($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',params);
const rpcMeta=async()=>(await db.query(`select oid,prosrc,proacl::text acl,prosecdef,proconfig from pg_proc where oid='${signature}'::regprocedure`)).rows[0];
const photos=async uid=>(await db.query('select portrait_path,my_number_front_path,my_number_back_path from public.employee_registration_invites where auth_user_id=$1',[uid])).rows[0];
const snapshot=async()=>(await db.query("select jsonb_build_object('invites',(select jsonb_agg(to_jsonb(i) order by id) from public.employee_registration_invites i),'members',(select jsonb_agg(to_jsonb(m) order by user_id) from public.company_members m),'notifications',(select count(*) from private.fixture_notifications))::text s")).rows[0].s;
async function actor(uid,fn,role='authenticated'){
 await db.exec('begin');try{await db.query("select set_config('fixture.uid',$1,true)",[uid??'']);await db.exec(`set local role ${role}`);await fn();}finally{await db.exec('rollback');}
}
let checks=0;
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid,name text,phone_e164 text,status text,created_at timestamptz default now(),expires_at timestamptz default now()+interval '1 day',password_changed_at timestamptz,identity_verified_at timestamptz,address text,blood_type text,family_composition text,emergency_relation text,emergency_name text,emergency_phone text,emergency_address text,portrait_path text,my_number_front_path text,my_number_back_path text,submitted_at timestamptz);
 create table private.fixture_notifications(id uuid default gen_random_uuid(),company_id uuid,recipient uuid,kind text,action text,target uuid);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$insert into private.fixture_notifications(company_id,recipient,kind,action,target) values($1,$2,$3,$6,$7) returning id$$;
 grant usage on schema auth,private to authenticated,anon;`);
 await db.exec(capture.functions.find(f=>f.proname==='account_access_allowed').definition);await db.exec(original);
 await db.exec(`revoke all on function ${signature} from public,anon,authenticated,service_role;grant execute on function ${signature} to authenticated,service_role;
 insert into public.company_members values('${company}','${owner}','owner');
 insert into public.employee_registration_invites(id,company_id,auth_user_id,status,password_changed_at,portrait_path,my_number_front_path,my_number_back_path) values
 ('${id(11)}','${company}','${legacy}','profile_pending',now(),'fixture/legacy/portrait.png','fixture/legacy/front.png','fixture/legacy/back.png'),
 ('${id(12)}','${company}','${fresh}','profile_pending',now(),null,null,null);`);

 const initial=await snapshot(),meta=await rpcMeta(),originalPhotos=await photos(legacy);
 await db.exec(fs.readFileSync(path.join(here,'onboarding_photo_retention.sql.review-only'),'utf8'));
 const retained=await rpcMeta(); await db.exec(candidate);
 const safe=()=>db.query('select public.save_employee_onboarding_profile_without_photos($1,$2,$3,$4,$5,$6,$7)',params.slice(0,7));
 const invoke=async(uid,fn)=>actor(uid,async()=>{await fn();await db.exec('reset role');});
 for(const uid of [legacy,fresh])await invoke(uid,async()=>{await safe();await db.exec('reset role');assert.deepEqual(await photos(uid),uid===legacy?originalPhotos:{portrait_path:null,my_number_front_path:null,my_number_back_path:null});checks++;});
 // Exact rollback race: caller observed capability, operator restores original save,
 // then caller uses dedicated API. It must fail atomically, including notifications.
 await db.exec(original);
 await actor(legacy,async()=>{await assert.rejects(safe(),e=>e.code==='55000');checks++;});
 assert.equal(await snapshot(),initial);assert.deepEqual(await photos(legacy),originalPhotos);
 await invoke(fresh,async()=>{await safe();checks++;}); // NULL->NULL is safe even with old save.
 for(const uid of [null,owner])await actor(uid,async()=>{await assert.rejects(safe(),e=>e.code==='42501');checks++;});
 await actor(null,async()=>{await assert.rejects(safe(),e=>e.code==='42501');checks++;},'anon');
 await db.exec(`insert into private.account_deletion_access_restrictions values('${legacy}')`);await actor(legacy,async()=>{await assert.rejects(safe(),e=>e.code==='42501');checks++;});await db.exec('delete from private.account_deletion_access_restrictions');
 await db.exec(fs.readFileSync(path.join(here,'onboarding_photo_retention.sql.review-only'),'utf8').replace(/create function private.read_employee_onboarding_photo_capability\(\)[\s\S]*?commit;/,'commit;'));
 await invoke(legacy,async()=>{await db.exec('reset role');await db.query("update public.employee_registration_invites set portrait_path='fixture/concurrent/latest.png' where auth_user_id=$1",[legacy]);await db.exec('set local role authenticated');await safe();await db.exec('reset role');assert.equal((await photos(legacy)).portrait_path,'fixture/concurrent/latest.png');checks++;});
 await actor(legacy,async()=>{await assert.rejects(db.query('select public.save_employee_onboarding_profile_without_photos($1,$2,$3,$4,$5,$6,$7)',[null,...params.slice(1,7)]),/required onboarding field missing/);checks++;});
 await db.exec(`insert into public.employee_registration_invites(id,company_id,auth_user_id,status,password_changed_at) values('${id(99)}','${company}','${legacy}','profile_pending',now())`);
 await actor(legacy,async()=>{await assert.rejects(safe(),e=>e.code==='42501');checks++;});await db.query('delete from public.employee_registration_invites where id=$1',[id(99)]);
 const acl=(await db.query("select has_function_privilege('anon','public.save_employee_onboarding_profile_without_photos(text,text,text,text,text,text,text)','execute') anon,has_function_privilege('service_role','private.save_employee_onboarding_profile_without_photos(text,text,text,text,text,text,text)','execute') service,has_column_privilege('authenticated','public.employee_registration_invites','portrait_path','select') path")).rows[0];assert.deepEqual(acl,{anon:false,service:false,path:false});checks++;
 await db.exec('drop function public.save_employee_onboarding_profile_without_photos(text,text,text,text,text,text,text);drop function private.save_employee_onboarding_profile_without_photos(text,text,text,text,text,text,text)');
 await actor(legacy,async()=>{await assert.rejects(safe(),e=>e.code==='42883');checks++;});
 await db.exec('drop function public.employee_onboarding_photo_capability();drop function private.read_employee_onboarding_photo_capability()');await db.exec(original);
 assert.deepEqual(await rpcMeta(),meta);assert.equal(await snapshot(),initial);assert.deepEqual(await photos(legacy),originalPhotos);checks++;
 console.log(`PASS ${checks} dedicated omission-RPC SQL checks: old-save rollback fails atomically, legacy/new NULL safe, ACL and data/notifications/source restored. No production apply.`);
}catch(e){console.error('Safe-save fixture failed:',e.code??'',String(e.message).split('\n')[0]);process.exitCode=1;}finally{await db.close();}
