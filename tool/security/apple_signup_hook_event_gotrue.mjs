// Disposable CI only. Observe real before-user-created email/phone events.
// Google OAuth is not executed by this probe; keep that limitation explicit.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,randomUUID} from 'node:crypto';

const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-apple-event-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
let phase='setup',db,started=false,owned=false,lastStatus;
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],
 {cwd:root,timeout,maxBuffer:1024*1024,env:process.env});

try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');
 let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`)
  .replaceAll('54321','53971').replaceAll('54322','53972').replaceAll('54320','53970')
  .replaceAll('54323','53973').replaceAll('54324','53974').replaceAll('54327','53977')
  .replaceAll('54329','53979').replaceAll('127.0.0.1:3000','127.0.0.1:53971')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 const sms=/([\[]auth\.sms[\]][\s\S]*?)(?=\n[\[]|$)/;
 assert.ok(sms.test(config));
 config=config.replace(sms,section=>section.replace('enable_signup = false','enable_signup = true'));
 assert.match(config,/\[auth\.sms\]\s*\n[^[]*enable_signup = true/);
 config+='\n[auth.hook.before_user_created]\nenabled = true\nuri = "pg-functions://postgres/private/fixture_apple_signup_hook_observer"\n';
 await fs.writeFile(configPath,config,{mode:0o600});
 await cli(['migration','new','fixture_apple_signup_hook_observer']);
 const migrations=path.join(workdir,'supabase/migrations');
 const files=(await fs.readdir(migrations)).filter(name=>name.endsWith('.sql'));assert.equal(files.length,1);
 const guard=await fs.readFile(path.join(root,'tool/security/apple_existing_account_signup_guard.sql.review-only'),'utf8');
 const observer=await fs.readFile(path.join(root,'tool/security/apple_signup_hook_event_observer.fixture.sql'),'utf8');
 await fs.writeFile(path.join(migrations,files[0]),guard+'\n'+observer,{mode:0o600});
 phase='disposable-stack';
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);
 assert.equal(existing.stdout.trim(),'');
 started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(api.port,'53971');
 assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'53972');assert.equal(database.pathname,'/postgres');
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
 assert.equal(settings.external.email,true);assert.equal(settings.external.phone,true);
 phase='actual-email-signup-event';
 const password=`Fixture-${randomBytes(24).toString('hex')}!A1`;
 const rejected=async response=>{assert.ok(response.status>=400&&response.status<500,phase);const body=await response.json();assert.equal(body.access_token,undefined);};
 await rejected(await request('/auth/v1/signup',{body:{email:`event-${randomUUID()}@example.invalid`,password,data:{provider:'apple',providers:['apple']}}}));
 phase='actual-phone-signup-event';
 await rejected(await request('/auth/v1/signup',{body:{phone:'+15555550101',password,channel:'sms',data:{provider:'apple'}}}));
 phase='actual-hook-observation-and-guard-compatibility';
 const observed=(await db.query('select * from private.fixture_apple_signup_hook_observations order by provider')).rows;
 assert.deepEqual(observed,[
  {provider:'email',providers_type:'array',providers_contains_provider:true,guard_allowed:true},
  {provider:'phone',providers_type:'array',providers_contains_provider:true,guard_allowed:true}
 ]);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 const images=await run('docker',['ps','--filter',`name=${project}`,'--format','{{.Image}}']);
 const authImages=images.stdout.trim().split('\n').filter(value=>/gotrue/.test(value));
 assert.equal(authImages.length,1);
 const version=authImages[0].match(/:v([0-9]+\.[0-9]+\.[0-9]+)$/)?.[1]??'unknown';
 console.log(JSON.stringify({result:'PASS disposable real GoTrue signup hook event observation',
  auth_version:version,observed_providers:['email','phone'],providers_array_present:true,
  actual_guard_allowed_both:true,all_creations_intentionally_denied_by_observer:true,
  actual_new_users:0,sms_sent:false,email_sent:false,google_oauth_observed:false,
  google_source_contract_checked_separately:'v2.197.0 shared SignupParams.ToUserModel',
  production_changed:false,production_hook_ready:false}));
} catch(error) {
 console.error(JSON.stringify({result:'FAIL disposable signup hook event observation',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,
  private_response_omitted:true}));process.exitCode=1;
} finally {
 if(db)await db.end().catch(()=>{});
 let stopped=!started;
 if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable signup observer stack cleanup failed; private runner logs omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}
