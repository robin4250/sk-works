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
import {downloadOwnVaultPdf} from './personal_vault_delivery_candidate.mjs';
import {createVaultCreateOnlyUpload} from './storage_create_only_transport.mjs';

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
 // Exercise the create-only candidate against actual Storage. This fixture
 // bridge uses the disposable trusted exporter credential, not an owner upload
 // policy or production service key. No app write grant is added.
 const uploadOrigin='https://vault-disposable.invalid';
 const createOnly=createVaultCreateOnlyUpload({origin:uploadOrigin,bucket,
  publishableKey:'sb_publishable_isolated_gateway_marker',
  authorizationHeader:async()=>'Bearer fixture_exporter_marker',
  fetchImpl:async(url,options)=>{
   const checked=new URL(url);assert.equal(checked.origin,uploadOrigin);
   const headers={...options.headers,apikey:service};
   if(service.startsWith('sb_secret_'))delete headers.Authorization;
   else headers.Authorization=`Bearer ${service}`;
   const localUrl=new URL(checked.pathname,api);
   const raw=await fetch(localUrl,{...options,headers});
   lastStatus=raw.status;
   // The production transport must keep its exact-origin response check. This
   // fixture bridge verifies the actual loopback response then remaps it to the
   // requested synthetic origin without exposing disposable gateway credentials.
   assert.equal(raw.redirected,false);assert.equal(raw.url,localUrl.href);
   const bridged=new Response(raw.body,{status:raw.status,statusText:raw.statusText,headers:raw.headers});
   Object.defineProperty(bridged,'url',{value:checked.href});
   return bridged;
  }});
 const uploadInput={ownerId:owner.user.id,artifactKey:artifact,pdfSha256:hash,bytes};
 phase='create-only-upload';
 const uploaded=await createOnly(uploadInput);
 assert.equal(uploaded.status,'created_unverified');
 assert.equal('immutableVersion' in uploaded,false);
 const stored=(await db.query('select version from storage.objects where bucket_id=$1 and name=$2',[bucket,objectPath])).rows;
 assert.equal(stored.length,1);assert.equal(typeof stored[0].version,'string');
 const version=stored[0].version;
 phase='create-only-duplicate';
 const replacementBytes=Buffer.from('%PDF-1.7\nchanged snapshot must not replace original\n%%EOF\n');
 await assert.rejects(createOnly({...uploadInput,bytes:replacementBytes,pdfSha256:digest(replacementBytes)}),
  /vault_upload_outcome_unknown/);
 const unchanged=(await db.query('select version from storage.objects where bucket_id=$1 and name=$2',[bucket,objectPath])).rows;
 assert.equal(unchanged.length,1);assert.equal(unchanged[0].version,version);
 const originalRead=await request(`/storage/v1/object/${bucket}/${objectPath}`,{admin:true,method:'GET'});
 assert.equal(originalRead.status,200);assert.deepEqual(Buffer.from(await originalRead.arrayBuffer()),bytes);
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
 await db.query(await fs.readFile(path.join(root,'docs/review/personal-vault24/read-api.sql.review-only'),'utf8'));
 await db.query(await fs.readFile(path.join(root,'docs/review/personal-vault25-delivery/source-binding.sql.review-only'),'utf8'));
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
 // Exercise the current v2 coordinator against real PostgREST RPCs and real
 // private Storage bytes. The proof issuer and metadata adapter below remain
 // test fixtures: this does not claim independent content inspection/custody.
 await db.query("notify pgrst, 'reload schema'");
 async function rpc(token,name,body={}) {
  return json(await request('/rest/v1/rpc/'+name,{token,body}));
 }
 phase='rpc-schema-ready';
 let ready=false;
 for(let attempt=0;attempt<40;attempt++) {
  const response=await request('/rest/v1/rpc/personal_vault24_list_mine',{token:owner.access_token,body:{}});
  if(response.status===200){await response.json();ready=true;break;}
  const error=await response.json();assert.equal(error.code,'PGRST202');await wait(250);
 }
 assert.equal(ready,true);
 const sourceBody={mid,artifact};
 const source=(await rpc(owner.access_token,'personal_vault25_source_mine',sourceBody))[0];
 assert.equal(source.kind,'own_payroll');assert.equal(source.snapshot_hash,hash);
 const fixtureProof={passed:true,policy:'own-snapshot-v2',sourceBinding:source,
  ownerId:owner.user.id,manifestId:mid,artifactKey:artifact,kind:'own_payroll',pdfSha256:hash};
 let coordinatorDownloads=0;
 const servicesFor=token=>({
  liveActor:async()=>{const user=await json(await request('/auth/v1/user',{token,method:'GET'}));
   return {ownerId:user.id,sessionId:claims(token).session_id};},
  listMine:()=>rpc(token,'personal_vault24_list_mine'),
  sourceMine:(manifest,artifactKey)=>rpc(token,'personal_vault25_source_mine',{mid:manifest,artifact:artifactKey}),
  itemMine:async(manifest,artifactKey)=>(await rpc(token,'personal_vault24_item_mine',{mid:manifest,artifact:artifactKey}))
   .map(row=>({...row,byte_length:Number(row.byte_length)})),
  storageMetadata:async(p,v)=>{const rows=(await db.query('select version from storage.objects where bucket_id=$1 and name=$2',[bucket,p])).rows;
   return rows.length===1&&rows[0].version===v?{objectPath:p,version:v,contentType:'application/pdf',byteLength:bytes.length}:null;},
  download:async(...args)=>{coordinatorDownloads++;return download(token)(...args);},
  trustedPrivacyProof:async()=>structuredClone(fixtureProof),
 });
 const input={manifestId:mid,artifactKey:artifact},ownerServices=servicesFor(owner.access_token);
 phase='v2-owner-coordinator';assert.deepEqual(await downloadOwnVaultPdf(input,ownerServices),bytes);
 phase='v2-foreign-before-download';
 const beforeForeign=coordinatorDownloads;
 await assert.rejects(downloadOwnVaultPdf(input,servicesFor(other.access_token)));
 assert.equal(coordinatorDownloads,beforeForeign);
 phase='v2-proof-source-mismatch';
 for(const field of ['source_company_id','source_worker_id','source_id','source_revision','snapshot_hash','manifest_hash','kind']) {
  const altered=structuredClone(fixtureProof);altered.sourceBinding[field]='different';
  await assert.rejects(downloadOwnVaultPdf(input,{...ownerServices,trustedPrivacyProof:async()=>altered}),/vault_privacy_proof_rejected/);
 }
 phase='v2-old-proof-rejected';
 await assert.rejects(downloadOwnVaultPdf(input,{...ownerServices,trustedPrivacyProof:async()=>({...fixtureProof,policy:'own-snapshot-v1'})}),/vault_privacy_proof_rejected/);
 phase='v2-real-source-change';
 await assert.rejects(downloadOwnVaultPdf(input,{...ownerServices,trustedPrivacyProof:async()=>{
  await db.query("update personal_vault24_candidate.items set source_revision='fixture-r2' where manifest_id=$1",[mid]);
  return structuredClone(fixtureProof);
 }}),/vault_source_changed/);
 await db.query("update personal_vault24_candidate.items set source_revision='fixture-r1' where manifest_id=$1",[mid]);
 phase='v2-revoked-during-inspection';
 await assert.rejects(downloadOwnVaultPdf(input,{...ownerServices,trustedPrivacyProof:async()=>{
  await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[claims(owner.access_token).session_id]);
  return structuredClone(fixtureProof);
 }}));
 await db.query('update auth.sessions set not_after=null where id=$1',[claims(owner.access_token).session_id]);
 phase='v2-source-anonymous-acl';
 const anonymousSource=await request('/rest/v1/rpc/personal_vault25_source_mine',{body:sourceBody});
 assert.notEqual(anonymousSource.status,200);await anonymousSource.arrayBuffer();
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
  create_only_post:true,duplicate_upload_preserves_original:true,upload_ack_not_immutable_proof:true,
  owner_download:true,foreign_and_anon_denied:true,public_path_denied:true,broad_policy_not_bypass:true,
  version_and_completion_bound:true,expired_and_revoked_session_denied:true,size_and_hash_rejected:true,
  loopback_gateway_bridge:true,real_postgrest_source_binding:true,v2_coordinator:true,
  exact_source_proof_required:true,source_change_and_midflight_revocation_denied:true,
  synthetic_privacy_proof_issuer:true,synthetic_storage_metadata_adapter:true,synthetic_catalog:true,immutable_custody:false,content_inspection:false,production_changed:false}));
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
