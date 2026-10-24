// Disposable CI only. Real GoTrue credential enrollment; synthetic Google
// identity fixture and email bootstrap are NOT real Google OAuth/Face ID proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID} from 'node:crypto';

const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-enrollment-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
let phase='setup',db,started=false,owned=false,lastStatus;
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],
 {cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));

try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');
 let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`)
  .replaceAll('54321','53961').replaceAll('54322','53962').replaceAll('54320','53960')
  .replaceAll('54323','53963').replaceAll('54324','53964').replaceAll('54327','53967')
  .replaceAll('54329','53969').replaceAll('127.0.0.1:3000','127.0.0.1:53961')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 phase='disposable-stack';
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);
 assert.equal(existing.stdout.trim(),'');
 started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(api.port,'53961');
 assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'53962');assert.equal(database.pathname,'/postgres');
 const anon=status.ANON_KEY??status.PUBLISHABLE_KEY,service=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof anon,'string');assert.equal(typeof service,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 async function request(route,{token,body,admin=false,method='POST'}={}) {
  const url=new URL(route,api);assert.equal(url.origin,api.origin);
  const key=admin?service:anon;
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(15000),
   headers:{apikey:key,...(admin&&!service.startsWith('sb_secret_')?{Authorization:`Bearer ${service}`}:{ }),
    ...(token?{Authorization:`Bearer ${token}`}:{ }),...(body===undefined?{}:{'Content-Type':'application/json'})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})});
  lastStatus=response.status;return response;
 }
 async function json(response,expected=200) {assert.equal(response.status,expected,phase);return response.json();}
 phase='provider-readonly';
 const settings=await json(await request('/auth/v1/settings',{method:'GET'}));
 assert.equal(settings.external.email,true);assert.equal(settings.external.phone,false);
 phase='create-disposable-bootstrap-user';
 const email=`enrollment-${randomUUID()}@example.invalid`;
 const seed=await json(await request('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));
 phase='generate-private-bootstrap-link';
 const link=await json(await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
 phase='bootstrap-link-token-shape';
 assert.equal(typeof link.hashed_token,'string');
 phase='verify-real-bootstrap-session';
 const original=await json(await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
 phase='bootstrap-session-user-and-claims';
 assert.equal(original.user.id,seed.id);assert.equal(typeof claims(original.access_token).session_id,'string');
 phase='bootstrap-session-database-binding';
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',
  [claims(original.access_token).session_id,seed.id])).rows[0].n,1);
 phase='synthetic-google-identity-fixture';
 // Transform only this disposable user's identity after email bootstrap. This
 // models Google-only identity storage and an empty password hash; it does not
 // simulate Google's consent. Admin-created bootstrap users can receive a
 // random credential internally, so the OAuth-only seed is established here.
 const identity=(await db.query('select id from auth.identities where user_id=$1',[seed.id])).rows;
 assert.equal(identity.length,1);
 await db.query(`update auth.identities set provider='google',provider_id=$1,
   identity_data=jsonb_build_object('sub',$1::text,'email',$2::text,'email_verified',true)
   where user_id=$3`,[seed.id,email,seed.id]);
 await db.query(`update auth.users set encrypted_password='',raw_app_meta_data=jsonb_build_object('provider','google','providers',jsonb_build_array('google')) where id=$1`,[seed.id]);
 phase='verify-google-only-seed-has-no-password';
 assert.equal((await db.query("select coalesce(encrypted_password,'')='' absent from auth.users where id=$1",[seed.id])).rows[0].absent,true);
 await db.query(`create table public.company_members(company_id uuid,user_id uuid,role text);
  alter table public.company_members enable row level security;
  grant select on public.company_members to authenticated;
  create policy own on public.company_members for select to authenticated using(user_id=(select auth.uid()));
  create schema private;
  create table private.fixture_secondary_password(user_id uuid primary key,password_digest text not null);`);
 const company=randomUUID();
 await db.query("insert into public.company_members values($1,$2,'owner')",[company,seed.id]);
 await db.query("insert into private.fixture_secondary_password values($1,'synthetic-secondary-digest-retained')",[seed.id]);
 await db.query("notify pgrst,'reload schema'");
 const readUser=async token=>json(await request('/auth/v1/user',{method:'GET',token}));
 const roles=async token=>request(`/rest/v1/company_members?select=company_id,role&user_id=eq.${seed.id}`,{method:'GET',token});
 let beforeRoles;
 for(let i=0;i<40;i++){const r=await roles(original.access_token);if(r.status===200){beforeRoles=await r.json();break;}assert.ok([404,503].includes(r.status));await wait(250);}
 assert.equal(beforeRoles?.length,1);
 const before=await readUser(original.access_token);
 assert.equal(before.id,seed.id);assert.deepEqual(before.identities.map(x=>x.provider),['google']);
 const preserved=async()=> (await db.query(`select jsonb_build_object(
  'members',(select jsonb_agg(to_jsonb(x) order by user_id,company_id) from public.company_members x),
  'secondary',(select jsonb_agg(to_jsonb(x) order by user_id) from private.fixture_secondary_password x),
  'google',(select jsonb_agg(to_jsonb(x) order by id) from auth.identities x where provider='google')) value`)).rows[0].value;
 const beforeHash=digest(await preserved());
 phase='add-first-password-through-real-user-endpoint';
 const password=`Fixture-${randomBytes(24).toString('hex')}!A1`;
 await json(await request('/auth/v1/user',{method:'PUT',token:original.access_token,body:{password}}));
 const after=await readUser(original.access_token);
 assert.equal(after.id,before.id);assert.ok(after.identities.some(x=>x.provider==='google'&&x.id===before.identities[0].id));
 assert.equal(digest(await preserved()),beforeHash);
 assert.deepEqual(await json(await roles(original.access_token)),beforeRoles);
 phase='actual-password-login-same-user';
 const signed=await json(await request('/auth/v1/token?grant_type=password',{body:{email,password}}));
 assert.equal(signed.user.id,seed.id);assert.notEqual(claims(signed.access_token).session_id,claims(original.access_token).session_id);
 assert.deepEqual(await json(await roles(signed.access_token)),beforeRoles);
 assert.equal((await readUser(original.access_token)).id,seed.id);
 assert.equal(digest(await preserved()),beforeHash);
 phase='wrong-password-denied';
 const denied=await request('/auth/v1/token?grant_type=password',{body:{email,password:'incorrect-fixture-password'}});
 assert.equal(denied.status,400);assert.equal((await denied.json()).access_token,undefined);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,1);
 console.log(JSON.stringify({result:'PASS isolated real GoTrue first-password enrollment',
  initial_password_absent:true,initial_google_identity:'synthetic-storage-fixture',bootstrap:'real-GoTrue-email-magiclink',
  real_user_update:true,real_password_login_same_uid:true,original_session_retained:true,
  google_identity_unchanged:true,company_roles_unchanged:true,secondary_fixture_unchanged:true,
  phone_enabled:false,actual_google_oauth:false,actual_faceid:false,production_changed:false}));
} catch(error) {
 console.error(JSON.stringify({result:'FAIL disposable first-password enrollment',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,
  private_response_omitted:true}));process.exitCode=1;
} finally {
 if(db)await db.end().catch(()=>{});
 let stopped=!started;
 if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable enrollment stack cleanup failed; private runner logs omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}
