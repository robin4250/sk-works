// Real GoTrue/JWT to existing pending adapter in an isolated CI stack only.
// Private bucket/catalog export are synthetic fixtures; no activation.
// Disposable CI only; email bootstrap is not real Google OAuth/Face ID proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {createVaultStorageDownload} from './storage_download_transport.mjs';

const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated disposable CI without hosted credentials required');
const project=`sko-vault-storage-${randomBytes(8).toString('hex')}`,workdir=path.join(parent,project);
let phase='setup',db,pool,started=false,owned=false,lastStatus;
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],
 {cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
const digest=value=>createHash('sha256').update(value).digest('hex');
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
 await cli(['start','--exclude','edge-runtime,realtime,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
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

 phase='real-users';
 const makeUser=async()=>{
  const email='vault-'+randomUUID()+'@example.invalid';
  const seed=await json(await request('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));
  const link=await json(await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
  const signed=await json(await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
  assert.equal(signed.user.id,seed.id);
  assert.equal((await json(await request('/auth/v1/user',{token:signed.access_token,method:'GET'}))).id,seed.id);
  return signed;
 };
 const owner=await makeUser(),other=await makeUser();
 const bucket='personal-pdf-vault',artifact='a'.repeat(64),mid=randomUUID();
 const objectPath=`personal-vault/${owner.user.id}/${artifact}.pdf`;
 const bytes=Buffer.from('%PDF-1.7\nsynthetic private own payroll snapshot\n%%EOF\n');
 const hash=digest(bytes);
 phase='private-bucket';
 await json(await request('/storage/v1/bucket',{admin:true,body:{id:bucket,name:bucket,public:false}}));
 const uploaded=await fetch(new URL(`/storage/v1/object/${bucket}/${objectPath}`,api),{method:'POST',redirect:'error',
  signal:AbortSignal.timeout(15000),headers:{apikey:service,
   ...(!service.startsWith('sb_secret_')?{Authorization:`Bearer ${service}`}:{ }),
   'Content-Type':'application/pdf','x-upsert':'false'},body:bytes});
 lastStatus=uploaded.status;assert.equal(uploaded.status,200);
 const stored=(await db.query('select version from storage.objects where bucket_id=$1 and name=$2',[bucket,objectPath])).rows;
 assert.equal(stored.length,1);assert.equal(typeof stored[0].version,'string');
 const version=stored[0].version;
 phase='existing-catalog-and-policies';
 // Reuse the existing read-only catalog and Storage policy candidate. The
 // exporter inventory/master gate is NOT exercised: catalog rows are fixtures.
 await db.query(`create schema private;
 create table private.master_admins(user_id uuid primary key,enabled boolean);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$select hashtextextended($1::text,0)$$;
 create function private.account_access_allowed() returns boolean language sql as $$select not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
 create function private.require_lifecycle_features(text[]) returns void language plpgsql as $$begin raise exception 'export fixture disabled';end$$;`);
 await db.query(await fs.readFile(path.join(root,'docs/review/personal-vault24/feature-fixture/native-auth-functions.sql'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'docs/review/personal-vault24/catalog.sql.review-only'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'docs/review/personal-vault24/storage-access.sql.review-only'),'utf8'));
 await db.query(`insert into personal_vault24_candidate.manifests(id,owner_id,source_company_id,source_worker_id,transition_request_id,
 snapshot_hash,manifest_hash,expected_count,status,completed_at) values($1,$2,$3,$4,$5,$6,$6,1,'complete',clock_timestamp())`,
 [mid,owner.user.id,randomUUID(),randomUUID(),randomUUID(),hash]);
 await db.query(`insert into personal_vault24_candidate.items(manifest_id,artifact_key,kind,source_id,source_revision,snapshot_hash,
 object_path,object_version,pdf_hash,byte_length) values($1,$2,'own_payroll',$3,'fixture-r1',$4,$5,$6,$4,$7)`,
 [mid,artifact,randomUUID(),hash,objectPath,version,bytes.length]);
 // A broad unrelated permissive policy must not bypass the candidate's
 // restrictive vault boundary.
 await db.query('create policy fixture_broad_select on storage.objects for select to public using(true)');
 const syntheticOrigin='https://vault-disposable.invalid';
 function download(token) {
  return createVaultStorageDownload({origin:syntheticOrigin,bucket,
   publishableKey:'sb_publishable_isolated_gateway_marker',authorizationHeader:async()=>`Bearer ${token}`,
   fetchImpl:(url,options)=>{
    const checked=new URL(url);assert.equal(checked.origin,syntheticOrigin);
    // Test-only transport bridge: exact loopback URL and disposable gateway key.
    // The real JWT and all Storage response bytes pass through unchanged.
    return fetch(new URL(checked.pathname,api),{...options,headers:{...options.headers,apikey:anon}});
   }});
 }
 const opts={maxBytes:bytes.length,expectedSha256:hash};
 phase='owner-stream';assert.deepEqual(await download(owner.access_token)(objectPath,version,opts),bytes);
 phase='foreign-user';await assert.rejects(download(other.access_token)(objectPath,version,opts));
 phase='anonymous';
 const anonymous=await request(`/storage/v1/object/${bucket}/${objectPath}`,{method:'GET'});
 assert.notEqual(anonymous.status,200);await anonymous.arrayBuffer();
 phase='public-path';
 const publicRead=await request(`/storage/v1/object/public/${bucket}/${objectPath}`,{method:'GET'});
 assert.notEqual(publicRead.status,200);await publicRead.arrayBuffer();
 phase='size-and-hash';
 await assert.rejects(download(owner.access_token)(objectPath,version,{...opts,maxBytes:bytes.length-1}));
 await assert.rejects(download(owner.access_token)(objectPath,version,{...opts,expectedSha256:'b'.repeat(64)}));
 phase='version-binding';
 await db.query('update personal_vault24_candidate.items set object_version=$1 where manifest_id=$2',['wrong-version',mid]);
 await assert.rejects(download(owner.access_token)(objectPath,version,opts));
 await db.query('update personal_vault24_candidate.items set object_version=$1 where manifest_id=$2',[version,mid]);
 phase='pending-manifest';
 await db.query("update personal_vault24_candidate.manifests set status='pending',completed_at=null where id=$1",[mid]);
 await assert.rejects(download(owner.access_token)(objectPath,version,opts));
 await db.query("update personal_vault24_candidate.manifests set status='complete',completed_at=clock_timestamp() where id=$1",[mid]);
 phase='expired-session';
 const session=claims(owner.access_token).session_id;
 await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[session]);
 await assert.rejects(download(owner.access_token)(objectPath,version,opts));
 await db.query('update auth.sessions set not_after=null where id=$1',[session]);
 phase='revoked-session';
 await db.query('delete from auth.sessions where id=$1',[session]);
 await assert.rejects(download(owner.access_token)(objectPath,version,opts));
 assert.equal((await db.query('select count(*)::int n from storage.objects where bucket_id=$1',[bucket])).rows[0].n,1);
 console.log(JSON.stringify({result:'PASS isolated real GoTrue and Storage boundary',real_gotrue:true,real_storage:true,
  owner_download:true,foreign_and_anon_denied:true,public_path_denied:true,broad_policy_not_bypass:true,
  version_and_completion_bound:true,expired_and_revoked_session_denied:true,size_and_hash_rejected:true,
  loopback_gateway_bridge:true,synthetic_catalog:true,immutable_custody:false,content_inspection:false,production_changed:false}));
} catch(error) {
 console.error(JSON.stringify({result:'FAIL isolated real GoTrue and Storage boundary',phase,
  kind:error?.code==='ERR_ASSERTION'?'assertion':/^[0-9A-Z]{5}$/.test(error?.code??'')?'postgres':'other',
  sqlstate:/^[0-9A-Z]{5}$/.test(error?.code??'')?error.code:null,last_http_status:lastStatus,private_response_omitted:true}));
 process.exitCode=1;
}finally{
 if(db)await db.end().catch(()=>{});
 let stopped=!started;
 if(started){try{await cli(['stop','--no-backup'],120000);stopped=true;}catch{process.exitCode=1;console.error('Disposable vault stack cleanup failed; private logs omitted.');}}
 if(owned&&stopped)await fs.rm(workdir,{recursive:true,force:true});
}
