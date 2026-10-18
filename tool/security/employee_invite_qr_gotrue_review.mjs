// REVIEW FIXTURE ONLY. Fresh, disposable localhost GoTrue/Data API; never hosted.
// Usage: node ... <local-status.json> <pinned-pg-module.js>
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {randomUUID,randomBytes} from 'node:crypto';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../..');
if(!process.env.CI || Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Isolated CI without hosted credentials required');
const status=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const api=new URL(status.API_URL),database=new URL(status.DB_URL);
assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(database.hostname,'127.0.0.1');assert.equal(database.pathname,'/postgres');
const {Client}=await import(pathToFileURL(path.resolve(process.argv[3])).href);
const db=new Client({connectionString:database.href});
const anon=status.ANON_KEY,service=status.SERVICE_ROLE_KEY;
assert.equal(typeof anon,'string');assert.equal(typeof service,'string');
let phase='freshness';
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
async function request(route,{token,body,method='POST',admin=false}={}){
 const url=new URL(route,api);assert.equal(url.origin,api.origin);
 return fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:admin?service:anon,Authorization:`Bearer ${admin?service:(token??anon)}`,...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
}
const expectStatus=(r,n)=>assert.equal(r.status,n,`Status mismatch: ${phase}`);
const rpc=(name,token)=>request('/rest/v1/rpc/'+name,{token,body:{}});
async function markerDenied(r){assert.ok([400,500].includes(r.status));const data=await r.json();assert.equal(data.code,'P0001');assert.equal(data.message,'pending employee invitation not found');}
const capture=JSON.parse(read('tool/security/onboarding_storage_catalog.json'));
try{
 await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select to_regnamespace('private') is null absent")).rows[0].absent,true);
 // NO product hook/Auth/provider change. This isolates default GoTrue credential
 // semantics plus the exact source marker/state RPC, not hosted hook equivalence.
 await db.query(`create schema private;create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid unique,name text,phone_e164 text,status text,created_at timestamptz default now(),expires_at timestamptz,password_changed_at timestamptz);alter table public.employee_registration_invites enable row level security;revoke all on public.employee_registration_invites from public,anon,authenticated;`);
 await db.query(capture.rpcs.find(f=>f.proname==='employee_onboarding_state').definition);
 const marker=read('supabase/migrations/20261013210756_guard_employee_invitation_initial_password_expiry.sql');
 await db.query(marker.slice(marker.indexOf('CREATE OR REPLACE FUNCTION')));
 for(const signature of ['employee_onboarding_state()','mark_employee_initial_password_changed()'])await db.query(`revoke all on function public.${signature} from public,anon;grant execute on function public.${signature} to authenticated`);
 await db.query("notify pgrst,'reload schema'");
 const password=`Fixture-${randomBytes(24).toString('hex')}!A1`,phone='+819000000001';
 phase='create-synthetic-phone-user';let r=await request('/auth/v1/admin/users',{admin:true,body:{phone,password,phone_confirm:true,app_metadata:{sko_registration_type:'employee_invite'}}});expectStatus(r,200);const user=await r.json();assert.ok(user.id);
 const id=randomUUID(),company=randomUUID(),worker=randomUUID();
 await db.query("insert into public.employee_registration_invites values($1,$2,$3,$4,'Synthetic employee',$5,'invited',now(),now()-interval '1 hour',null)",[id,company,worker,user.id,phone]);
 const login=()=>request('/auth/v1/token?grant_type=password',{body:{phone,password}});
 phase='expired-temporary-password-login';r=await login();expectStatus(r,200);const first=await r.json();assert.ok(first.access_token);
 // Poll schema only through an own-state read would cancel the invite; marker
 // must first reject without invoking that state-read path.
 phase='expired-marker-without-state-read';let markerSeen=false;
 for(let i=0;i<30;i++){r=await rpc('mark_employee_initial_password_changed',first.access_token);if(r.status!==404){markerSeen=true;break;}await new Promise(resolve=>setTimeout(resolve,200));}
 assert.equal(markerSeen,true);await markerDenied(r);
 assert.equal((await db.query('select status from public.employee_registration_invites where id=$1',[id])).rows[0].status,'invited');
 phase='expired-own-state-cancels';r=await rpc('employee_onboarding_state',first.access_token);expectStatus(r,200);assert.equal((await r.json()).status,'cancelled');
 phase='same-expired-qr-reuse';r=await login();expectStatus(r,200);assert.equal((await r.json()).user.id,user.id);
 phase='valid-invite-repeat-before-password-change';await db.query("update public.employee_registration_invites set status='invited',expires_at=now()+interval '1 hour' where id=$1",[id]);r=await login();expectStatus(r,200);const second=await r.json();r=await login();expectStatus(r,200);assert.equal((await r.json()).user.id,user.id);
 // Reproduce actual client order: updateUser(password), then marker. A fresh
 // expiry between these calls rejects DB progression after Auth changed.
 phase='auth-password-update-before-marker';const replacement=`Fixture-${randomBytes(24).toString('hex')}!B2`;
 r=await request('/auth/v1/user',{token:second.access_token,method:'PUT',body:{password:replacement}});expectStatus(r,200);
 await db.query("update public.employee_registration_invites set expires_at=now()-interval '1 hour' where id=$1",[id]);
 r=await rpc('mark_employee_initial_password_changed',second.access_token);await markerDenied(r);
 phase='old-password-after-password-change';r=await login();assert.ok([400,422].includes(r.status));
 phase='replacement-password-after-expired-marker';r=await request('/auth/v1/token?grant_type=password',{body:{phone,password:replacement}});expectStatus(r,200);
 phase='prechange-jwt-observation';r=await request('/auth/v1/user',{token:first.access_token,method:'GET'});const oldJwtUserStatus=r.status;assert.ok([200,401,403].includes(oldJwtUserStatus));
 r=await rpc('employee_onboarding_state',first.access_token);const oldJwtRpcStatus=r.status;assert.ok([200,401,403].includes(oldJwtRpcStatus));
 if(r.status===200)assert.equal((await r.json()).status,'cancelled');
 // Readable synthetic status only, never JWT/phone/password/body/keys/IDs.
 console.log(JSON.stringify({result:'BASELINE OBSERVED; NOT A FIX',expired_login_issued_token:true,expired_marker_denied:true,cancelled_qr_login_issued_token:true,valid_qr_repeat_before_password_change:true,old_password_denied_after_change:true,replacement_login_after_marker_denial:true,old_jwt_auth_status:oldJwtUserStatus,old_jwt_rpc_status:oldJwtRpcStatus,production_equivalence:false}));
}catch{console.error(`Employee invite isolated review failed at ${phase}; private response and connection details omitted.`);process.exitCode=1;}
finally{await db.end().catch(()=>{});}
