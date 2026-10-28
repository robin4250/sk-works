// Disposable local-only GoTrue + PostgREST proof. No hosted credentials or data.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,randomUUID} from 'node:crypto';
const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||process.env.SKO_INVOICE_NOTICE_AUTH_HOOK!=='contract-v1'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('isolated CI without hosted credentials required');
const project='sko-invoice-approval-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let started=false,owned=false,db,phase='setup';
try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;await cli(['init']);
 const file=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(file,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`);
 for(const [a,b] of [['54321','53911'],['54322','53912'],['54320','53910'],['54323','53913'],['54324','53914'],['54327','53917'],['54329','53919']])config=config.replaceAll(a,b);
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');await fs.writeFile(file,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='start';started=true;await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout),api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53911');
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(database.hostname)&&database.port==='53912'&&database.pathname==='/postgres');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof publicKey,'string');assert.equal(typeof serviceKey,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 async function request(route,{token,body,service=false,headers={}}={}) {
  const u=new URL(route,api);assert.equal(u.origin,api.origin);
  return fetch(u,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:service?serviceKey:publicKey,...(service&&!serviceKey.startsWith('sb_'+'secret_')?{Authorization:'Bearer '+serviceKey}:{}),...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})});
 }
 const users={},tokens={},password='fixture-'+randomBytes(20).toString('hex')+'!A1';
 phase='real-local-auth';
 for(const name of ['owner','admin','foreign']) {
  const created=await request('/auth/v1/admin/users',{service:true,body:{email:name+'@example.invalid',password,email_confirm:true}});assert.equal(created.status,200);users[name]=await created.json();
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});assert.equal(login.status,200);
  const session=await login.json();tokens[name]=session.access_token;const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
  assert.equal(claims.sub,users[name].id);assert.ok(claims.session_id);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
 }
 phase='integrated-fixture';
 const integrationPath=path.join(workdir,'combined-integration.mjs'), runtimePath=path.join(workdir,'combined-runtime.mjs');
 const src=await fs.readFile('docs/review/invoice-month-close/verify_integration.mjs','utf8');
 const marker='console.log(JSON.stringify({real_refresh_preview_gate_readiness:true';
 if(src.split(marker).length!==2)throw Error('integration marker changed');
 const combined=await fs.readFile('docs/review/invoice-month-close/combined_finance_inject.txt','utf8');
 await fs.writeFile(integrationPath,src.replace(marker,()=>combined+'\n'+marker),{mode:0o600});
 await fs.copyFile('docs/review/invoice-month-close/combined_native_runtime.mjs',runtimePath);
 const opt={cwd:root,timeout:600000,maxBuffer:4*1024*1024,env:{...process.env,
  SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL:database.href,SKO_ADJUSTMENT_ROOT:root,SKO_COMBINED_ACTOR:users.owner.id,SKO_COMBINED_TOKEN:tokens.owner,SKO_COMBINED_ANON:publicKey,SKO_COMBINED_API:api.origin,
  SKO_LEGACY_GUARD_SQL:path.join(workdir,'legacy-notice-guard.sql'),SKO_APPROVER_CORE:path.join(workdir,'approver-core.sql'),
  SKO_PREVIEW_WRAPPER:path.join(root,'invoice-calculation-candidate/docs/review/invoice-correction-preview/verify.mjs'),
  SKO_PREVIEW_SQL:path.join(root,'invoice-calculation-candidate/docs/review/invoice-correction-preview/preview.sql.review-only'),
  SKO_NOTIFY_TRIGGER:path.join(root,'invoice-calculation-candidate/docs/review/invoice-correction-preview/integration_trigger_bodies.sql.review-only'),
  ...Object.fromEntries([['SKO_NOTICE_SQL','notification.sql.review-only'],['SKO_PUBLIC_ENTRY_SQL','public_entry.sql.review-only'],['SKO_APPROVAL_GUARD_SQL','approval_guard.sql.review-only'],['SKO_APPROVAL_ENTRY_SQL','approval_entry.sql.review-only'],['SKO_DELIVERY_SQL','notification_delivery.sql.review-only'],['SKO_NOTIFICATION_READINESS_SQL','notification_readiness.sql.review-only'],['SKO_APPROVAL_SQL','approve.sql.review-only'],['SKO_GUARDED_SQL','guarded.sql.review-only'],['SKO_MONTH_CLOSE_SQL','precheck.sql.review-only']].map(([k,n])=>[k,path.join(root,'docs/review/invoice-month-close',n)]))}};
 await run('python3',['docs/review/invoice-month-close/generate_legacy_notice_guard.py',opt.env.SKO_NOTIFY_TRIGGER,opt.env.SKO_LEGACY_GUARD_SQL],opt);
 await run('python3',['docs/review/invoice-month-close/generate_approver_core.py',opt.env.SKO_PREVIEW_SQL,opt.env.SKO_APPROVER_CORE],opt);
 const result=await run(process.execPath,[integrationPath,runtimePath],opt);
 if(!result.stdout.includes('"disposable_gotrue_real_readiness_notification_approval":true'))throw Error('combined proof missing');
 console.log('PASS disposable GoTrue/PostgREST + real candidate readiness + notification + atomic approval; route source synthetic');
} catch(error){console.error('invoice notice isolated test failed at '+phase+': '+String(error?.message??error).slice(0,500));process.exitCode=1;}
finally {if(db)await db.end().catch(()=>{});if(started)await cli(['stop','--no-backup'],180000).catch(()=>{process.exitCode=1;});if(owned)await fs.rm(workdir,{recursive:true,force:true}).catch(()=>{process.exitCode=1;});}
