// Disposable TLS/PGlite harness. Auth /user is an exact-token HMAC fixture,
// not real GoTrue; existing session/company binding SQL is loaded verbatim.
import * as fs from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createServer as reservePort} from 'node:net';
import {request} from 'node:https';
import {tmpdir} from 'node:os';import {join} from 'node:path';
import {createHash,createHmac,generateKeyPairSync,sign,timingSafeEqual} from 'node:crypto';
import {PGlite} from '../../fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
import {createArchiveReadbackServerCandidate} from '../src/archive-readback-server-candidate.mjs';
import {createArchiveReadbackHTTPSVerifierCandidate} from '../src/archive-readback-https-candidate.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const digest=x=>createHash('sha256').update(x).digest('hex');
export async function serverFixture(t){
 const root=await fs.mkdtemp(join(tmpdir(),'sko-readback-server-'));await fs.chmod(root,0o700);
 const tlsKey=join(root,'server.key'),tlsCert=join(root,'server.crt');
 execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',tlsKey,'-out',tlsCert,'-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1'],{stdio:'ignore'});
 const tls={key:await fs.readFile(tlsKey),cert:await fs.readFile(tlsCert)},keys=generateKeyPairSync('ed25519'),pin=keys.publicKey.export({format:'jwk'}),db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema extensions;
 create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid()returns uuid language sql stable as $$select(auth.jwt()->>'sub')::uuid$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,deleted_at timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table private.master_admins(user_id uuid primary key,enabled boolean);
 create table company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
 create table user_secondary_credentials(user_id uuid primary key,password_hash text,failed_attempts integer default 0,locked_until timestamptz,updated_at timestamptz);
 create function private.account_deletion_barrier_key(p uuid)returns bigint language sql immutable as $$select hashtextextended(p::text,781)$$;
 create function extensions.digest(p bytea,alg text)returns bytea language sql immutable as $$select sha256(p)$$;
 create function extensions.gen_random_bytes(n integer)returns bytea language sql volatile as $$select decode(replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),'hex')$$;
 create function extensions.crypt(p text,h text)returns text language sql immutable as $$select 'fixture:'||p$$;`);
 for(const f of JSON.parse(await fs.readFile(new URL('../../free-worker-candidate/issuer/current-core-fixtures.json',import.meta.url),'utf8')))await db.exec(f.definition);
 await db.exec(await fs.readFile(new URL('../../free-worker-candidate/issuer/management-issuer.sql.review-only',import.meta.url),'utf8'));
 await db.exec(await fs.readFile(new URL('../src/archive-readback-registry.sql.review-only',import.meta.url),'utf8'));
 await db.exec(await fs.readFile(new URL('../src/archive-readback-runtime-role.sql.review-only',import.meta.url),'utf8'));
 const actor=id(1),sid=id(2),company=id(3),other=id(4),otherSid=id(5),foreignCompany=id(6),authority=id(7);
 await db.query('insert into auth.users(id)values($1),($2)',[actor,other]);
 await db.query('insert into auth.sessions values($1,$2,null),($3,$4,null)',[sid,actor,otherSid,other]);
 await db.query('insert into private.master_admins values($1,true),($2,true)',[actor,other]);
 await db.query("insert into company_members values($1,$2,'owner'),($3,$4,'owner')",[company,actor,foreignCompany,other]);
 await db.query("insert into user_secondary_credentials(user_id,password_hash)values($1,'fixture:a'),($2,'fixture:b')",[actor,other]);
 for(const [deployment,c,a]of[['archive_a',company,actor],['archive_b',foreignCompany,other]])await db.query('insert into security_management_issuer_private.deployments(deployment_id,company_id,owner_id,enabled,key_id,key_version,manager_jwk) values($1,$2,$3,true,$1,1,$4)',[deployment,c,a,pin]);
 const byteRoot=join(root,'bytes');await fs.mkdir(byteRoot,{mode:0o700});const store=await createArchiveByteStoreCandidate({enabled:true,directory:byteRoot});
 const make=async(c,event,payload)=>store.retain({company_id:c,event_id:event,revision:2,snapshot_sha256:'a'.repeat(64),payload_sha256:digest(payload),payload});
 const own=await make(company,id(8),Buffer.from('opaque own fixture')),foreign=await make(foreignCompany,id(9),Buffer.from('opaque foreign fixture'));
 const register=async(d,owner,deployment)=>db.query(`insert into archive_readback_private.authority_records(object_id,authority_id,company_id,owner_id,deployment_id,event_id,revision,snapshot_sha256,payload_sha256,byte_length)values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,[d.object_id,authority,d.company_id,owner,deployment,d.event_id,d.revision,d.snapshot_sha256,d.payload_sha256,d.byte_length]);
 // Test-owned seeding only: the candidate has no authenticated registration API.
 await register(own,actor,'archive_a');await register(foreign,other,'archive_b');
 let tail=Promise.resolve(),acquisitions=0,restores=0,signatures=0;const releases=[],queries=[],authCalls=[];
 const pool={async connect(){const previous=tail;let unlock;tail=new Promise(r=>unlock=r);await previous;acquisitions++;let released=false;
  return {query:async(...args)=>{queries.push(args[0]);return db.query(...args);},release(destroy=false){if(released)throw Error('double release');released=true;releases.push(destroy);(destroy?db.exec('rollback').catch(()=>{}):Promise.resolve()).then(unlock);}};}};
 const authSecret='fixture-Auth-token-validation-only-not-a-live-secret';
 function token({sub=actor,session=sid,role='authenticated',exp=Math.floor(Date.now()/1000)+3600,metadata={}}={}){
  const head=Buffer.from(JSON.stringify({alg:'HS256'})).toString('base64url'),body=Buffer.from(JSON.stringify({sub,session_id:session,role,exp,iat:Math.floor(Date.now()/1000),is_anonymous:false,user_metadata:metadata})).toString('base64url');
  return `${head}.${body}.${createHmac('sha256',authSecret).update(`${head}.${body}`).digest('base64url')}`;
 }
 const fetchImpl=async(url,options)=>{
  authCalls.push({url,headers:options.headers});if(url!=='https://auth-fixture.invalid/auth/v1/user')throw Error('fixed Auth origin required');
  const raw=options.headers.Authorization?.slice(7),parts=raw?.split('.')??[];
  if(parts.length!==3)return Response.json({}, {status:401});
  const signature=Buffer.from(parts[2],'base64url'),expected=createHmac('sha256',authSecret).update(`${parts[0]}.${parts[1]}`).digest();
  if(signature.length!==expected.length||!timingSafeEqual(signature,expected))return Response.json({}, {status:401});
  const c=JSON.parse(Buffer.from(parts[1],'base64url').toString());if(c.exp*1000<=Date.now())return Response.json({}, {status:401});
  return Response.json({id:c.sub,is_anonymous:false,user_metadata:c.user_metadata});
 };
 const base={enabled:true,tls,auth:{url:'https://auth-fixture.invalid',publicKey:'fixture-public-key',serviceBearer:token({role:'service_role'}),fetchImpl},pool,
  store:{async restore(d){restores++;return store.restore(d);}},authorityId:authority,key:pin,
  signObservation:async bytes=>{signatures++;return sign(null,bytes,keys.privateKey);},timeoutMs:5000};
 const servers=[];
 async function start(options={}){
  // Reserve an ephemeral test port before constructing the exact configured
  // origin. The production factory never discovers/listens on a host itself.
  const reservation=reservePort();await new Promise(r=>reservation.listen(0,'127.0.0.1',r));const port=reservation.address().port;await new Promise(r=>reservation.close(r));
  const endpoint=`https://127.0.0.1:${port}/readback`,server=createArchiveReadbackServerCandidate({...base,endpoint,...options});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});servers.push(server);
  const client=(bearer=token())=>createArchiveReadbackHTTPSVerifierCandidate({enabled:true,endpoint,bearer,ca:tls.cert,authorityId:authority,key:pin,timeoutMs:10000});
  const raw=(body,{bearer=token(),headers={},path='/readback',method='POST'}={})=>new Promise((resolve,reject)=>{
   const bytes=Buffer.from(typeof body==='string'?body:JSON.stringify(body));
   const req=request(endpoint,{method,path,ca:tls.cert,agent:false,headers:{authorization:`Bearer ${bearer}`,'content-type':'application/json','content-length':bytes.length,...headers}},res=>{
    const chunks=[];res.on('data',b=>chunks.push(b));res.on('error',reject);res.once('end',()=>resolve({status:res.statusCode,body:Buffer.concat(chunks).toString()}));});req.on('error',reject);req.end(bytes);
  });
  return {server,endpoint,client,raw};
 }
 t.after(async()=>{for(const s of servers){s.closeAllConnections();await new Promise(r=>s.close(r));}await tail;await db.close();await fs.rm(root,{recursive:true,force:true});});
 return {db,pool,store,base,start,token,actor,sid,company,other,otherSid,authority,own,foreign,register,releases,queries,authCalls,signBytes:bytes=>sign(null,bytes,keys.privateKey),
  counts:()=>({acquisitions,restores,signatures}),async clean(){await tail;return (await db.query("select auth.uid() as actor,nullif(current_setting('request.jwt.claims',true),'') as jwt")).rows[0];}};
}
