// Disposable local-only GoTrue + PostgREST proof. No hosted credentials or data.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,randomUUID} from 'node:crypto';
const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||process.env.SKO_OWNER_PREVIEW_AUTH_HOOK!=='contract-v1'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('isolated CI without hosted credentials required');
const project='sko-invoice-owner-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
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
 phase='synthetic-app-setup';
 await db.query(`create schema private;
  create function private.account_access_allowed() returns boolean language sql stable as $$select true$$;
  create table private.master_admins(user_id uuid primary key,enabled boolean not null);
  create table public.company_members(company_id uuid,user_id uuid,role text);
  create table public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_invoices boolean);
  create table public.invoices(id uuid primary key,company_id uuid,snapshot jsonb);
  create function private.has_company_feature(c uuid,f text) returns boolean language sql stable as $$select exists(select 1 from public.company_members m where m.company_id=c and m.user_id=auth.uid() and (m.role in ('owner','admin') or exists(select 1 from public.member_feature_permissions p where p.company_id=c and p.user_id=m.user_id and p.can_manage_invoices)))$$;
  create schema invoice_correction_preview_private;create table invoice_correction_preview_private.fixture(invoice_id uuid,value jsonb);
  create function invoice_correction_preview_private.preview(p_id uuid) returns jsonb language sql as $$select value from invoice_correction_preview_private.fixture where invoice_id=p_id$$;`);
 const base='docs/candidates/invoice_revision_staging_20261027/';
 await db.query(await fs.readFile('tool/reauthentication-helper.fixture.sql','utf8'));
 for(const fileName of ['owner-preview.sql.review-only','owner-preview-api.sql.review-only']) await db.query(await fs.readFile(base+fileName,'utf8'));
 const company=randomUUID(),otherCompany=randomUUID(),invoice=randomUUID();
 await db.query('insert into private.master_admins values($1,true),($2,true)',[users.owner.id,users.foreign.id]);
 await db.query("insert into public.company_members values($1,$2,'owner'),($1,$3,'admin'),($4,$5,'owner')",[company,users.owner.id,users.admin.id,otherCompany,users.foreign.id]);
 const original={days:5};await db.query('insert into public.invoices values($1,$2,$3)',[invoice,company,JSON.stringify(original)]);
 const proposal={original_invoice_id:invoice,original_invoice_fingerprint:'a'.repeat(64),source_fingerprint:'b'.repeat(64),calculation_blocked:false,proposed_snapshot:{sites:[{days:6},{days:1}]},subtotal:700,tax:70,welfare:0,grand_total:770};
 await db.query('insert into invoice_correction_preview_private.fixture values($1,$2)',[invoice,JSON.stringify(proposal)]);
 for(const role of ['anon','authenticated','service_role']) {
  const acl=(await db.query("select has_function_privilege($1,'public.invoice_owner_reference_preview_candidate(uuid,text,text)','EXECUTE') allowed",[role])).rows[0].allowed;
  assert.equal(acl,false,'candidate must ship with no client grant');
 }
 // ONLY in disposable DB: expose candidate RPC to authenticated for HTTP proof.
 await db.query('grant execute on function public.invoice_owner_reference_preview_candidate(uuid,text,text) to authenticated');
 await db.query("notify pgrst,'reload schema'");
 const body={p_invoice_id:invoice,p_expected_source:null,p_expected_original:null};
 const rpc=(body,token,headers)=>request('/rest/v1/rpc/invoice_owner_reference_preview_candidate',{body,token,headers});
 phase='gate-and-jwt';let response;
 for(let i=0;i<40;i++){response=await rpc(body,tokens.owner);if(response.status!==404&&response.status!==503)break;await new Promise(r=>setTimeout(r,250));}
 assert.notEqual(response.status,200,'gate must default OFF');
 await db.query('update invoice_owner_preview_candidate.settings set enabled=true');
 response=await rpc(body,tokens.owner);assert.equal(response.status,200);const shown=await response.json();assert.equal(shown.status,'unissued_reference_only');assert.equal(shown.grand_total,770);
 for(const token of [tokens.admin,tokens.foreign,undefined]) {response=await rpc(body,token);assert.notEqual(response.status,200,'nonmaster, other company and anonymous must be denied');}
 response=await rpc(body,undefined,{Origin:'https://attacker.example',Cookie:'untrusted=1'});assert.notEqual(response.status,200,'cookie-only cross-origin request has no authenticated session');
 await db.query("update invoice_correction_preview_private.fixture set value=jsonb_set(value,'{source_fingerprint}',to_jsonb($1::text))",['c'.repeat(64)]);
 response=await rpc({...body,p_expected_source:'b'.repeat(64),p_expected_original:'a'.repeat(64)},tokens.owner);assert.notEqual(response.status,200);assert.equal((await response.json()).code,'40001');
 response=await rpc({...body,p_expected_source:'c'.repeat(64),p_expected_original:null},tokens.owner);assert.notEqual(response.status,200);
 assert.deepEqual((await db.query('select snapshot from invoices where id=$1',[invoice])).rows[0].snapshot,original);
 phase='logout';response=await request('/auth/v1/logout',{token:tokens.owner});assert.equal(response.status,204);
 response=await rpc(body,tokens.owner);assert.notEqual(response.status,200,'revoked actual session must be denied');
 console.log('PASS isolated GoTrue session + PostgREST owner preview: role, gate, stale, cookie-only and logout; synthetic financial inputs');
} catch(error){console.error('owner-preview isolated test failed at '+phase+': '+String(error?.message??error).slice(0,500));process.exitCode=1;}
finally {if(db)await db.end().catch(()=>{});if(started)await cli(['stop','--no-backup'],180000).catch(()=>{process.exitCode=1;});if(owned)await fs.rm(workdir,{recursive:true,force:true}).catch(()=>{process.exitCode=1;});}
