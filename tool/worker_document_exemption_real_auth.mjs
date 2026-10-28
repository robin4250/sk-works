// Disposable real GoTrue -> PostgREST proof. No hosted endpoint is accepted.
// Application tables/account barrier are explicit synthetic fixtures.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,randomUUID} from 'node:crypto';

const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||
 Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
 throw Error('Dedicated isolated CI without hosted credentials required');
const project='sko-document-exemption-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],
 {cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let phase='setup',db,started=false,owned=false,lastHttp;
const id=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0');
try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,'project_id = "'+project+'"')
  .replaceAll('54321','53681').replaceAll('54322','53682').replaceAll('54320','53680')
  .replaceAll('54323','53683').replaceAll('54324','53684').replaceAll('54327','53687')
  .replaceAll('54329','53689').replaceAll('127.0.0.1:3000','127.0.0.1:53681')
  .replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter','name='+project,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='disposable-stack';started=true;
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor,mailpit'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout),api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.equal(api.protocol,'http:');assert.equal(api.hostname,'127.0.0.1');assert.equal(api.port,'53681');
 assert.equal(database.hostname,'127.0.0.1');assert.equal(database.port,'53682');assert.equal(database.pathname,'/postgres');
 const anon=status.ANON_KEY??status.PUBLISHABLE_KEY,service=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof anon,'string');assert.equal(typeof service,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 const authFns=async()=>(await db.query("select jsonb_agg(jsonb_build_object('oid',oid::text,'definition',pg_get_functiondef(oid)) order by oid) v from pg_proc where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].v;
 const originalAuthFns=await authFns();
 async function request(route,{token,body,admin=false,method='POST'}={}) {
  const url=new URL(route,api);assert.equal(url.origin,api.origin);const key=admin?service:anon;
  const r=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{
   apikey:key,...(admin&&!service.startsWith('sb_secret_')?{Authorization:'Bearer '+service}:{}),
   ...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},
   ...(body===undefined?{}:{body:JSON.stringify(body)})});lastHttp={route,status:r.status};return r;
 }
 async function json(r,expected=200){assert.equal(r.status,expected);return r.json();}
 const actors={};
 phase='real-auth-users';
 for(const name of ['owner','admin','manager','employee','viewer','foreign']) {
  const email='exemption-'+randomUUID()+'@example.invalid';
  const user=await json(await request('/auth/v1/admin/users',{admin:true,body:{email,email_confirm:true}}));
  const link=await json(await request('/auth/v1/admin/generate_link',{admin:true,body:{type:'magiclink',email}}));
  const session=await json(await request('/auth/v1/verify',{body:{type:'magiclink',token_hash:link.hashed_token}}));
  assert.equal(session.user.id,user.id);
  assert.equal((await json(await request('/auth/v1/user',{token:session.access_token,method:'GET'}))).id,user.id);
  const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
  assert.equal(claims.sub,user.id);assert.ok(claims.session_id);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,user.id])).rows[0].n,1);
  actors[name]={id:user.id,token:session.access_token,sid:claims.session_id};
 }
 phase='frozen-application-fixtures';
 await db.query(await fs.readFile('tool/worker_document_exemption_real_auth.fixture.sql','utf8'));
 const sessionSql=await fs.readFile('tool/staged/reauthentication_proofs.sql','utf8');
 const start=sessionSql.indexOf('create function private.require_reauthentication_session()');
 const end=sessionSql.indexOf('create function public.reauthentication_capabilities()',start);
 assert.ok(start>=0&&end>start);await db.query(sessionSql.slice(start,end));
 let attention=await fs.readFile('supabase/migrations/20260922010000_add_required_document_attention.sql','utf8');
 const marker="or wds.status in ('not_submitted','missing','expired')";assert.equal(attention.split(marker).length,2);
 // Match the already-reviewed bank/photo completion predicate; do not alter auth.
 attention=attention.replace(marker,marker+"\n      or (dr.name <> '銀行口座情報' and nullif(wds.attachment_path, '') is null)\n      or (dr.name = '銀行口座情報' and not exists(select 1 from public.worker_private_bank_accounts ba where ba.worker_id=v_worker_id and ba.company_id=v_company_id))");
 await db.query(attention);
 const attentionCatalog=async()=>(await db.query("select proowner,prosecdef,provolatile,proconfig,proacl from pg_proc where oid='public.current_user_required_document_attention()'::regprocedure")).rows;
 const originalAttention=await attentionCatalog();
 await db.query(await fs.readFile('docs/candidates/worker_document_exemption_20261027/install.sql.review-only','utf8'));
 assert.deepEqual(await attentionCatalog(),originalAttention);
 const company=id(1),other=id(2),worker=id(3),worker2=id(4),requirement=id(5),bank=id(6),photo=id(7);
 for(const [name,role] of [['owner','owner'],['admin','admin'],['manager','manager'],['employee','worker'],['viewer','viewer'],['foreign','admin']])
  await db.query('insert into public.company_members values($1,$2,$3)',[name==='foreign'?other:company,actors[name].id,role]);
 await db.query("insert into public.workers values($1,$2,$3,'active'),($4,$2,$5,'active')",[worker,company,actors.employee.id,worker2,actors.viewer.id]);
 for(const [rid,name,order] of [[requirement,'本人書類',1],[bank,'銀行口座情報',2],[photo,'健康保険証',3]])
  await db.query('insert into public.document_requirements values($1,$2,$3,true,true,$4)',[rid,company,name,order]);
 await db.query("insert into public.worker_document_statuses values($1,$2,$3,$4,'submitted',null),($5,$2,$6,$7,'submitted','saved/original.pdf')",
  [id(8),company,worker,photo,id(9),worker2,requirement]);
 const originalBusiness=(await db.query("select jsonb_build_object('workers',(select jsonb_agg(to_jsonb(x) order by id) from workers x),'requirements',(select jsonb_agg(to_jsonb(x) order by id) from document_requirements x),'statuses',(select jsonb_agg(to_jsonb(x) order by id) from worker_document_statuses x)) v")).rows[0].v;
 const protectedState=async()=>(await db.query("select jsonb_build_object('items',(select jsonb_agg(to_jsonb(x) order by company_id,worker_id,requirement_id) from private.worker_document_exemptions x),'events',(select jsonb_agg(to_jsonb(x) order by id) from private.worker_document_exemption_events x)) v")).rows[0].v;
 const rpc=(action,data,token)=>request('/rest/v1/rpc/worker_document_exemption',{token,body:{p_action:action,p_data:data}});
 const ok=async(action,data,who='owner')=>json(await rpc(action,data,actors[who].token));
 async function denied(action,data,token,code='42501') {
  const before=await protectedState(),r=await rpc(action,data,token),value=await r.json();
  assert.ok(r.status>=400);assert.equal(value.code,code);assert.deepEqual(await protectedState(),before);
 }
 const command=(version,active=true)=>({company_id:company,worker_id:worker,requirement_id:requirement,active,expected_version:version,reason:'合成本人事情を管理者が確認'});
 const attentionFor=async(who='employee')=>json(await request('/rest/v1/rpc/current_user_required_document_attention',{token:actors[who].token,body:{}}));
 phase='postgrest-cache';await db.query("notify pgrst,'reload schema'");
 for(let attempt=0;;attempt++){
  const r=await rpc('list',{company_id:company},actors.owner.token);
  if(r.status===200){assert.equal((await r.json()).can_manage,false);break;}
  const error=await r.json();if(error.code!=='PGRST202'||attempt===40)throw Error('Local schema cache unavailable');
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 phase='off-default';assert.equal((await attentionFor()).missing_count,3);
 await denied('set',command(0),actors.owner.token);
 await db.query('update private.worker_document_exemption_settings set enabled=true');
 phase='owner-grant';assert.equal((await ok('set',command(0))).item.version,1);
 assert.equal((await attentionFor()).missing_count,2);assert.equal((await ok('list',{company_id:company},'employee')).items.length,1);
 assert.equal((await ok('list',{company_id:company},'viewer')).items.length,0);
 await denied('set',command(1,false),actors.employee.token);
 await denied('set',command(1,false),actors.viewer.token);
 await denied('set',command(1,false),actors.foreign.token);
 await denied('list',{company_id:company},actors.foreign.token);
 await denied('list',{company_id:company},undefined);
 await denied('set',command(0),actors.owner.token,'40001');
 phase='metadata-cannot-grant';await json(await request('/auth/v1/user',{token:actors.viewer.token,method:'PUT',body:{data:{role:'owner',company_id:company,is_master:true}}}));
 await denied('set',command(1,false),actors.viewer.token);
 const tokenParts=actors.owner.token.split('.');tokenParts[2]=(tokenParts[2][0]==='A'?'B':'A')+tokenParts[2].slice(1);const forged=tokenParts.join('.');
 const beforeForged=await protectedState(),forgedResponse=await rpc('set',command(1,false),forged);
 assert.ok(forgedResponse.status>=400);assert.deepEqual(await protectedState(),beforeForged);
 phase='subadmin-revoke';assert.equal((await ok('set',command(1,false),'manager')).item.version,2);
 assert.equal((await attentionFor()).missing_count,3);
 assert.equal((await ok('set',command(2),'admin')).item.version,3);
 phase='off-preserves-saved';await db.query('update private.worker_document_exemption_settings set enabled=false');
 assert.equal((await attentionFor()).missing_count,2);assert.equal((await ok('list',{company_id:company})).items[0].active,true);
 assert.equal((await ok('list',{company_id:company})).can_manage,false);
 await denied('set',command(3,false),actors.owner.token);
 await db.query('update private.worker_document_exemption_settings set enabled=true');
 phase='live-session-revocation';
 const logout=await request('/auth/v1/logout?scope=local',{token:actors.manager.token});assert.ok([200,204].includes(logout.status));
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1',[actors.manager.sid])).rows[0].n,0);
 await denied('list',{company_id:company},actors.manager.token);await denied('set',command(3,false),actors.manager.token);
 phase='account-barrier';await db.query('insert into private.account_deletion_access_restrictions values($1)',[actors.owner.id]);
 await denied('set',command(3,false),actors.owner.token);
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[actors.owner.id]);
 phase='direct-private-acl';
 await db.query('begin');await db.query('set local role authenticated');
 try {await db.query('select * from private.worker_document_exemptions');assert.fail('private table accessible');}
 catch(e){assert.equal(e.code,'42501');}finally{await db.query('rollback');}
 const afterBusiness=(await db.query("select jsonb_build_object('workers',(select jsonb_agg(to_jsonb(x) order by id) from workers x),'requirements',(select jsonb_agg(to_jsonb(x) order by id) from document_requirements x),'statuses',(select jsonb_agg(to_jsonb(x) order by id) from worker_document_statuses x)) v")).rows[0].v;
 assert.deepEqual(afterBusiness,originalBusiness);assert.deepEqual(await authFns(),originalAuthFns);
 assert.deepEqual(await attentionCatalog(),originalAttention);
 assert.equal((await db.query('select count(*)::int n from private.worker_document_exemption_events')).rows[0].n,3);
 console.log('PASS real GoTrue JWT -> PostgREST exemption: owner/admin/subadmin, own read, viewer/foreign/anon/forged/metadata/session denial; OFF preservation; bank/photo attention retained; original business and auth functions retained');
 console.log('LIMIT synthetic application tables/account restriction fixture; no production deployment, independent backup/activation, real device, retention/recovery proof');
} catch(error) {
 console.error('FAIL isolated exemption phase='+phase+' code='+(typeof error?.code==='string'?error.code:'E2E_ASSERTION'));
 if(typeof error?.actual==='number'&&typeof error?.expected==='number')console.error(JSON.stringify({actual:error.actual,expected:error.expected}));
 if(lastHttp)console.error(JSON.stringify(lastHttp));process.exitCode=1;
} finally {
 if(db)await db.end().catch(()=>{});
 if(started)await cli(['stop','--no-backup']).catch(()=>{console.error('Owned exemption fixture cleanup failed');process.exitCode=1;});
 if(owned)await fs.rm(workdir,{recursive:true,force:true});
}
