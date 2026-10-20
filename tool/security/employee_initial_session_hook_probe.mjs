// DISPOSABLE CI ONLY. Reuses #1245 transport/freshness boundaries, not its baseline rerun.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {randomUUID,randomBytes} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
if(!process.env.CI || Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Disposable CI without hosted credentials required');
const status=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const api=new URL(status.API_URL),database=new URL(status.DB_URL);
assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(database.hostname,'127.0.0.1');assert.equal(database.pathname,'/postgres');
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href),Client=pg.Client??pg.default.Client;
const db=new Client({connectionString:database.href});
const anon=status.ANON_KEY,service=status.SERVICE_ROLE_KEY;
assert.equal(typeof anon,'string');assert.equal(typeof service,'string');
let phase='freshness';
const read=name=>fs.readFileSync(path.join(root,'tool/security',name),'utf8');
async function request(route,{token,body,method='POST',admin=false}={}){
 const url=new URL(route,api);assert.equal(url.origin,api.origin);
 return fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:admin?service:anon,Authorization:`Bearer ${admin?service:(token??anon)}`,...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
}
const login=(user,password=user.password)=>request('/auth/v1/token?grant_type=password',{body:{email:user.email,password}});
const rpc=(name,token)=>request('/rest/v1/rpc/'+name,{token,body:{}});
const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
async function created(tag){
 const email=`${tag}-${randomUUID()}@example.invalid`,password=`Fixture-${randomBytes(24).toString('hex')}!A1`;
 const r=await request('/auth/v1/admin/users',{admin:true,body:{email,password,email_confirm:true}});
 assert.equal(r.status,200,phase);const row=await r.json();assert.ok(row.id);
 return {id:row.id,email,password};
}
async function tokenFor(user){const r=await login(user);assert.equal(r.status,200,phase);const value=await r.json();assert.ok(value.access_token);return value;}
async function denied(r){assert.ok(r.status>=400&&r.status<600,phase);const value=await r.json();assert.equal(value.access_token,undefined);}
async function enroll(user,{state='pending',expired=false}={}){
 await db.query(`insert into private.fixture_employee_initial_targets(user_id,invite_id,company_id,worker_id,state,expires_at,password_at_issue)
 select $1,$2,$3,$4,$5,now()+case when $6 then interval '-1 hour' else interval '1 hour' end,encrypted_password from auth.users where id=$1`,[user.id,randomUUID(),randomUUID(),randomUUID(),state,expired]);
 await db.query('insert into public.fixture_employee_business_rows values($1,$2)',[user.id,'synthetic-private-business']);
}
async function restricted(token){
 let r=await rpc('fixture_employee_initial_state',token);assert.equal(r.status,200,phase);assert.equal(await r.json(),true);
 r=await rpc('fixture_employee_business_rpc',token);assert.equal(r.status,403,phase);
 r=await request('/rest/v1/fixture_employee_business_rows?select=*',{token,method:'GET'});assert.equal(r.status,403,phase);
}
try{
 await db.connect();
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 await db.query(read('employee_initial_session_hook_probe.sql'));
 phase='phone-remains-off';let r=await request('/auth/v1/settings',{method:'GET'});assert.equal(r.status,200);assert.equal((await r.json()).external.phone,false);
 phase='real-hook-session-visibility';const owner=await created('ordinary-owner-proxy');const ownerSession=await tokenFor(owner);
 const ownerClaims=claims(ownerSession.access_token);
 assert.equal(ownerClaims.sub,owner.id);assert.equal(ownerClaims.role,'authenticated');
 const observation=(await db.query('select session_visible,session_matches_user,method from private.fixture_employee_hook_observations where user_id=$1 order by ordinal desc limit 1',[owner.id])).rows[0];
 assert.ok(observation,'Actual GoTrue hook must run; no SQL-only substitute');
 assert.equal(observation.method,'password');
 if(!observation.session_visible||!observation.session_matches_user){
  console.log(JSON.stringify({result:'OBSERVED; live session binding prerequisite unavailable',...observation,phone_enabled:false,production_equivalence:false,product_issuer_connected:false,qr_v2_complete:false}));
 }else{
  phase='install-disposable-guard';await db.query(read('employee_initial_session_hook_guard.fixture.sql'));
  const acl=(await db.query("select has_function_privilege('authenticated','public.fixture_employee_initial_access_token_hook(jsonb)','execute') a,has_function_privilege('anon','public.fixture_employee_initial_access_token_hook(jsonb)','execute') n")).rows[0];assert.deepEqual(acl,{a:false,n:false});
  await db.query("notify pgrst,'reload schema'");
  // Schema-cache readiness uses the ordinary owner only; no target is consumed.
  for(let i=0;i<40;i++){r=await rpc('fixture_employee_business_rpc',ownerSession.access_token);if(r.status!==404)break;await new Promise(v=>setTimeout(v,250));}
  assert.equal(r.status,200);assert.equal(await r.json(),true);
  phase='ordinary-and-approved-user-preservation';const ownerAgain=await tokenFor(owner);assert.equal(claims(ownerAgain.access_token).role,'authenticated');
  const approvedExisting=await created('approved-employee-proxy');const approvedSession=await tokenFor(approvedExisting);assert.equal(claims(approvedSession.access_token).role,'authenticated');
  phase='expired-and-cancelled-deny-before-token';
  for(const options of [{expired:true},{state:'cancelled'}]){const user=await created('denied-invite');await enroll(user,options);await denied(await login(user));assert.equal((await db.query('select consumed_session_id from private.fixture_employee_initial_targets where user_id=$1',[user.id])).rows[0].consumed_session_id,null);}
  phase='actual-session-single-consume-and-replay';const target=await created('pending-invite');await enroll(target);const first=await tokenFor(target),firstClaims=claims(first.access_token);
  assert.equal(firstClaims.role,'fixture_initial_onboarding');assert.equal(firstClaims.sub,target.id);
  const linked=(await db.query('select s.user_id=s.user_id and s.user_id=$1 same_user,t.consumed_session_id=s.id same_session from auth.sessions s join private.fixture_employee_initial_targets t on t.user_id=s.user_id where s.id=$2',[target.id,firstClaims.session_id])).rows[0];assert.deepEqual(linked,{same_user:true,same_session:true});
  await restricted(first.access_token);await denied(await login(target));
  phase='refresh-retains-limited-role';r=await request('/auth/v1/token?grant_type=refresh_token',{body:{refresh_token:first.refresh_token}});assert.equal(r.status,200);const refreshed=await r.json();assert.equal(claims(refreshed.access_token).session_id,firstClaims.session_id);assert.equal(claims(refreshed.access_token).role,'fixture_initial_onboarding');
  phase='cancel-denies-existing-jwt-and-refresh';await db.query("update private.fixture_employee_initial_targets set state='cancelled' where user_id=$1",[target.id]);await denied(await rpc('fixture_employee_initial_state',first.access_token));await denied(await request('/auth/v1/token?grant_type=refresh_token',{body:{refresh_token:refreshed.refresh_token}}));
  phase='expiration-denies-existing-jwt';await db.query("update private.fixture_employee_initial_targets set state='pending',expires_at=now()-interval '1 second' where user_id=$1",[target.id]);await denied(await rpc('fixture_employee_initial_state',first.access_token));
  phase='reissue-generation-denies-old-jwt';await db.query("update private.fixture_employee_initial_targets set expires_at=now()+interval '1 hour',generation=generation+1,consumed_session_id=null where user_id=$1",[target.id]);await denied(await rpc('fixture_employee_initial_state',first.access_token));
  phase='concurrent-redemption-proxy';const racing=await created('racing-invite');await enroll(racing);const results=await Promise.all([login(racing),login(racing)]);assert.equal(results.filter(x=>x.status===200).length,1);for(const failed of results.filter(x=>x.status!==200))await denied(failed);
  phase='permanent-password-and-approval-cutoff';const finishing=await created('finishing-invite');await enroll(finishing);const initial=await tokenFor(finishing);
  const replacement=`Fixture-${randomBytes(24).toString('hex')}!B2`;
  r=await request('/auth/v1/user',{method:'PUT',token:initial.access_token,body:{password:replacement}});assert.equal(r.status,200);
  await db.query("update private.fixture_employee_initial_targets set state='approved' where user_id=$1",[finishing.id]);
  await denied(await rpc('fixture_employee_initial_state',initial.access_token));
  await denied(await rpc('fixture_employee_business_rpc',initial.access_token));
  r=await login(finishing,replacement);assert.equal(r.status,200);const permanent=await r.json();assert.equal(claims(permanent.access_token).sub,finishing.id);assert.equal(claims(permanent.access_token).role,'authenticated');
  assert.notEqual(claims(permanent.access_token).session_id,claims(initial.access_token).session_id);
  r=await rpc('fixture_employee_business_rpc',permanent.access_token);assert.equal(r.status,200);
  phase='old-password-stays-invalid';await denied(await login(finishing));
  console.log(JSON.stringify({result:'PASS isolated Auth hook/session prototype only',actual_hook_invoked:true,live_session_visible:true,actual_session_uid_bound:true,expired_cancelled_repeat_denied:true,concurrent_one_winner:true,initial_role_rest_rpc_denied:true,old_jwt_denied_on_lease_operations:true,fresh_permanent_session_after_approval:true,ordinary_and_existing_approved_email_proxy_preserved:true,phone_enabled:false,credential_mechanism:'email_proxy_NOT_phone_QR_proof',actual_google_or_faceid_e2e:false,product_issuer_connected:false,token_redemption_implemented:false,storage_graph_proven:false,production_equivalence:false,qr_v2_complete:false}));
 }
}catch{console.error(`Employee initial-session disposable probe failed at ${phase}; private responses and credentials omitted.`);process.exitCode=1;}
finally{await db.end().catch(()=>{});}
