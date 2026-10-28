// Real GoTrue/JWT to QR common public flag APIs in an isolated CI stack only.
// Master ownership and operation proofs are synthetic fixtures; no production activation.
// Disposable CI only. Real GoTrue credential enrollment; synthetic Google
// identity fixture and email bootstrap are NOT real Google OAuth/Face ID proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID,generateKeyPairSync} from 'node:crypto';
import {exerciseScannerRealAuth} from '../../../tool/qr-attendance/qr-scanner-real-auth-composition.mjs';

const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-qr-master-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
let phase='setup',db,pool,started=false,owned=false,lastStatus;
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
  .replaceAll('54321','53781').replaceAll('54322','53782').replaceAll('54320','53780')
  .replaceAll('54323','53783').replaceAll('54324','53784').replaceAll('54327','53787')
  .replaceAll('54329','53789').replaceAll('127.0.0.1:3000','127.0.0.1:53781')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 phase='disposable-stack';
 const existing=await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}']);
 assert.equal(existing.stdout.trim(),'');
 started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(api.port,'53781');
 assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'53782');assert.equal(database.pathname,'/postgres');
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

 phase='fixture-schema';
 const reviewRoot=path.join(root,'docs/review/qr-master-gate');
 let setup=await fs.readFile(path.join(reviewRoot,'qr-common-public-contract-test.sql'),'utf8');
 const cut="select set_config('fixture.actor'";
 assert.equal(setup.split(cut).length,2);
 setup=setup.slice(0,setup.indexOf(cut));
 const replaceOnce=(source,old,value)=>{assert.equal(source.split(old).length,2);return source.replace(old,value);};
 setup=replaceOnce(setup,'\\set ON_ERROR_STOP on\n','');
 setup=replaceOnce(setup,'create schema auth;','');
 const authStart=setup.indexOf('create function auth.uid()');
 const authEnd=setup.indexOf('create table private.proof_fixture');
 assert.ok(authStart>0&&authEnd>authStart);
 const liveBoundary=`
 create table private.fixture_master_owners(user_id uuid primary key);
 create table private.fixture_access_restrictions(user_id uuid primary key);
 create function public.is_current_user_master_admin() returns boolean language sql as $$
  select exists(select from private.fixture_master_owners where user_id=auth.uid()) $$;
 create function private.require_reauthentication_session() returns uuid
 language plpgsql security definer set search_path='' as $$
 declare actor uuid:=auth.uid();sid uuid;
 begin
  if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
    or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' then raise sqlstate '42501';end if;
  begin sid:=(auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then raise sqlstate '42501';end;
  if sid is null or exists(select from private.fixture_access_restrictions where user_id=actor) then raise sqlstate '42501';end if;
  perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
   and (banned_until is null or banned_until<=clock_timestamp()) for share;
  if not found then raise sqlstate '42501';end if;
  perform 1 from auth.sessions where id=sid and user_id=actor
   and (not_after is null or not_after>clock_timestamp()) for share;
  if not found then raise sqlstate '42501';end if;
  return sid;
 end $$;
 `;
 setup=setup.slice(0,authStart)+liveBoundary+setup.slice(authEnd);
 const includes=async source=>{
  const matches=[...source.matchAll(/^\\ir ([a-z0-9.-]+)$/gm)];
  for(const match of matches){const included=await includes(await fs.readFile(path.join(reviewRoot,match[1]),'utf8'));source=source.replace(match[0],()=>included);}
  return source;
 };
 setup=await includes(setup);
 assert.ok(!setup.includes('fixture.actor')&&!setup.includes('fixture.session')&&!setup.includes('fixture.master'));
 await db.query(setup);
 const makeUser=async()=>{
  const email='qr-master-'+randomUUID()+'@example.invalid';
  const seed=await json(await request('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));
  const link=await json(await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
  const signed=await json(await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
  assert.equal(signed.user.id,seed.id);return signed;
 };
 const owner=await makeUser(),worker=await makeUser();
 await db.query('insert into private.fixture_master_owners values($1)',[owner.user.id]);
 let acquisitions=0;
 const call=async(token,sql,params=[])=>{
  const response=await request('/auth/v1/user',{method:'GET',token});
  if(response.status!==200)throw Error('GoTrue rejected token');
  const user=await response.json(),c=claims(token);
  assert.equal(c.sub,user.id);assert.equal(c.role,'authenticated');
  assert.equal(c.is_anonymous,false);assert.equal(typeof c.session_id,'string');
  assert.ok(Number.isSafeInteger(c.exp)&&c.exp>Math.floor(Date.now()/1000));
  acquisitions++;
  await db.query('begin');
  try{
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(c)]);
   await db.query('set local role authenticated');
   const result=await db.query(sql,params);await db.query('commit');return result.rows[0]?.flags;
  }catch(error){await db.query('rollback');throw error;}
 };
 const read=token=>call(token,'select public.current_master_feature_flags() flags');
 const change=(token,enabled)=>call(token,"select public.set_master_feature_enabled_with_proof('qr_attendance',$1,$2) flags",[enabled,enabled?'fixture-bound-proof':'fixture-off-proof']);
 const auditCount=async()=>Number((await db.query('select count(*) from private.master_admin_audit_log')).rows[0].count);
 const clean=async()=>{
  const row=(await db.query("select auth.uid() actor,nullif(current_setting('request.jwt.claims',true),'') claims,current_user role")).rows[0];
  assert.equal(row.actor,null);assert.equal(row.claims,null);assert.equal(row.role,'postgres');
 };
 phase='owner-default-off';
 assert.equal((await read(owner.access_token)).qr_attendance,false);
 await assert.rejects(change(owner.access_token,true));assert.equal(await auditCount(),0);await clean();
 phase='owner-proof-fixture-enable';
 await db.query('update qr_attendance_private.public_contract_rollout set enabled=true');
 assert.equal((await change(owner.access_token,true)).qr_attendance,true);assert.equal(await auditCount(),1);await clean();
 phase='worker-read-but-not-change';
 assert.equal((await read(worker.access_token)).qr_attendance,true);
 await db.query('update private.proof_fixture set used=false');
 await assert.rejects(change(worker.access_token,false));assert.equal(await auditCount(),1);
 assert.equal((await db.query('select used from private.proof_fixture')).rows[0].used,false);await clean();
 phase='user-metadata-not-master';
 await json(await request('/auth/v1/user',{method:'PUT',token:worker.access_token,body:{data:{master:true,is_master_admin:true}}}));
 await assert.rejects(change(worker.access_token,false));assert.equal(await auditCount(),1);await clean();
 phase='tampered-token-before-db';
 const parts=owner.access_token.split('.'),altered={...claims(owner.access_token),sub:worker.user.id};
 const forged=[parts[0],Buffer.from(JSON.stringify(altered)).toString('base64url'),parts[2]].join('.');
 const before=acquisitions;await assert.rejects(read(forged));assert.equal(acquisitions,before);await clean();
 phase='restricted-user';
 await db.query('insert into private.fixture_access_restrictions values($1)',[owner.user.id]);
 await assert.rejects(read(owner.access_token));await assert.rejects(change(owner.access_token,false));await clean();
 await db.query('delete from private.fixture_access_restrictions');
 phase='owner-off-and-audit';
 assert.equal((await change(owner.access_token,false)).qr_attendance,false);assert.equal(await auditCount(),2);await clean();
 phase='scanner-real-auth-composition';
 await exerciseScannerRealAuth({db,database,api,anon,makeUser,request});await clean();
 phase='expired-real-session';
 await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[claims(owner.access_token).session_id]);
 await assert.rejects(read(owner.access_token));await assert.rejects(change(owner.access_token,true));await clean();
 await db.query('update auth.sessions set not_after=null where id=$1',[claims(owner.access_token).session_id]);
 phase='deleted-real-session';
 await db.query('delete from auth.sessions where id=$1',[claims(owner.access_token).session_id]);
 await assert.rejects(read(owner.access_token));await clean();
 phase='anonymous-acl';
 await db.query('begin');
 try{await db.query('set local role anon');await assert.rejects(db.query('select public.current_master_feature_flags()'));}
 finally{await db.query('rollback');}
 await clean();assert.equal(await auditCount(),2);
 console.log(JSON.stringify({result:'PASS isolated QR common real GoTrue boundary',real_gotrue_user_validation:true,
  real_auth_uid_and_session_rows:true,master_and_proof_synthetic:true,public_endpoint:false,
  production_changed:false,activation:false}));
}catch(error){
 console.error(JSON.stringify({result:'FAIL isolated QR common real GoTrue boundary',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,private_response_omitted:true}));
 process.exitCode=1;
}finally{
 if(db)await db.end().catch(()=>{});
 let stopped=!started;
 if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable QR stack cleanup failed; private logs omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}

