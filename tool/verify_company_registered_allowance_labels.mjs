// Disposable PG17 + actual local PostgREST. Session/identity data are synthetic.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHmac, createHash, randomUUID} from 'node:crypto';
const run = promisify(execFile);
const cid='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
const uid=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const sid=n=>`70000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const item=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
let db,container,phase='destination',checks=0;
const equal=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
const rejects=async(fn,pattern)=>{await assert.rejects(fn,pattern);checks++;};
const json=x=>JSON.stringify(x);
try{
 assert.equal(process.env.CI,'true');assert.equal(process.platform,'linux');
 assert.ok(!Object.keys(process.env).some(k=>/^SUPABASE_(URL|ACCESS_TOKEN|DB_PASSWORD|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
 const url=new URL(process.env.SKO_REGISTERED_LABELS_FIXTURE_URL??'');
 assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'5432');
 assert.equal(url.pathname,'/sko_registered_allowance_labels_fixture');assert.equal(url.username,'postgres');assert.equal(url.password,'fixture-only');
 const pg=(await import(process.argv[2])).default;db=new pg.Client({connectionString:url.href});await db.connect();
 const q=async(sql,args=[]) => (await db.query(sql,args)).rows[0]?.v;
 equal((await db.query("select current_setting('server_version_num')::int n")).rows[0].n>=170000,true);
 equal(await q("select count(*)::int v from pg_tables where schemaname='public'"),0);
 phase='source-matched-session-fixture';
 await db.query(`create role anon nologin;create role authenticated nologin;create role service_role nologin;
 create role fixture_authenticator login password 'fixture-only' noinherit;
 grant anon,authenticated,service_role to fixture_authenticator;
 create schema auth;create schema private;create schema company_common_allowance_private;create schema company_allowance_identity_private;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select nullif(auth.jwt()->>'sub','')::uuid$$;
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function private.account_access_allowed() returns boolean language sql stable as $$select case when auth.uid()='${uid(4)}'::uuid then false when auth.uid()='${uid(5)}'::uuid then null else auth.uid() is not null end$$;
 create table companies(id uuid primary key);create table company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
`);
 const structure=JSON.parse(await fs.readFile('tool/fixtures/company_registered_labels/catalog_structure.json','utf8'));
 for(const relation of structure.relations){
  const defaults={'uuid':"'00000000-0000-0000-0000-000000000000'::uuid",'text':"''::text",'integer':'0','bigint':'0','numeric':'0','timestamp with time zone':'clock_timestamp()'};
  const columns=relation.columns.map(c=>{assert.ok(defaults[c.type], 'reviewed fixture type');return `${c.name} ${c.type}${c.not_null?' not null default '+defaults[c.type]:''}`;});
  await db.query(`create table ${relation.name}(${columns.join(',')});alter table ${relation.name} enable row level security;revoke all on ${relation.name} from public,anon,authenticated,service_role;`);
 }
 await db.query('grant all on public.company_rate_settings to service_role;grant usage on schema public,company_common_allowance_private to authenticated;grant usage on schema public to anon,service_role');
 const original=await fs.readFile('tool/staged_company_common_allowances.sql.review-only','utf8');
 const match=/create function company_common_allowance_private\.session_id\(\)[\s\S]*?as \$\$([\s\S]*?)\$\$;/i.exec(original);
 assert.ok(match);equal(createHash('md5').update(match[1]).digest('hex'),'68c68f275c23a22ba06d060c2923b9b9');
 await db.query(match[0]);await db.query('revoke all on function company_common_allowance_private.session_id() from public,anon,authenticated,service_role');
 const unit=await fs.readFile('docs/candidates/company_registered_allowance_labels_20261024.sql.review-only','utf8');
 phase='drift-refused-before-install';
 await db.query("alter function company_common_allowance_private.session_id() volatile");
 await rejects(()=>db.query(unit),/session prerequisite differs/);await db.query('rollback');
 equal(await q("select to_regprocedure('public.read_company_registered_allowance_labels(uuid)') is null v"),true);
 await db.query('alter function company_common_allowance_private.session_id() stable');
 await db.query('alter table company_common_allowance_private.items add column unexpected_fixture_column text');
 await rejects(()=>db.query(unit),/source table catalog differs/);await db.query('rollback');
 await db.query('alter table company_common_allowance_private.items drop column unexpected_fixture_column');
 await db.query('grant select on company_common_allowance_private.items to authenticated');
 await rejects(()=>db.query(unit),/source table catalog differs/);await db.query('rollback');
 await db.query('revoke select on company_common_allowance_private.items from authenticated');
 await db.query(unit);
 await rejects(()=>db.query(unit),/already exists/);await db.query('rollback');
 phase='all-current-company-definitions';
 await db.query('insert into companies values($1),($2)',[cid,other]);
 for(const n of [1,2,4,5,6,7,8]){
  await db.query('insert into company_members values($1,$2,$3)',[cid,uid(n),n===1?'owner':'member']);
  if(n!==7)await db.query('insert into auth.sessions values($1,$2,$3)',[sid(n),uid(n),n===6?'2000-01-01':null]);
 }
 await db.query('insert into company_members values($1,$2,$3)',[other,uid(3),'owner']);
 await db.query('insert into auth.sessions values($1,$2,null)',[sid(3),uid(3)]);
 await db.query("insert into company_rate_settings(company_id,allowance_1_name,allowance_1_unit,allowance_2_name,allowance_2_unit,allowance_3_name,allowance_3_unit,allowance_1_amount_yen,allowance_2_amount_yen) values($1,'旧登録A','回','旧登録B','件',null,'回',87654321,0),($2,'OTHER-COMPANY-NAME','回',null,'回',null,'回',123,0)",[cid,other]);
 await db.query('insert into company_allowance_identity_private.state(company_id,version) values($1,2)',[cid]);
 await db.query('insert into company_common_allowance_private.state(company_id,version) values($1,3)',[cid]);
 for(const n of [1,2])await db.query('insert into company_allowance_identity_private.identities(id,company_id,slot,generation,retired_at) values($1,$2,$3,$4,null)',[item(n),cid,n,n]);
 let n=10;
 for(const type of ['daily','hourly','monthly'])for(const unitName of ['hour','day','month']){
  await db.query('insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen,position,retired_at) values($1,$2,$3,$4,$5,$6,87654321,$7,null)',[item(n++),cid,type,unitName==='month'?'deduction':'earning',unitName,`${type}/${unitName}`,n]);
 }
 await db.query("insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen,position,retired_at) values($1,$2,'daily','earning','day','RETIRED-NAME',87654321,99,clock_timestamp()),($3,$4,'daily','earning','day','OTHER-COMPANY-NAME',87654321,1,null)",[item(90),cid,item(91),other]);
 const protectedData=()=>q(`select jsonb_build_object('rates',(select jsonb_agg(to_jsonb(x) order by company_id) from company_rate_settings x),'identities',(select jsonb_agg(to_jsonb(x) order by id) from company_allowance_identity_private.identities x),'legacy_state',(select jsonb_agg(to_jsonb(x) order by company_id) from company_allowance_identity_private.state x),'items',(select jsonb_agg(to_jsonb(x) order by id) from company_common_allowance_private.items x),'common_state',(select jsonb_agg(to_jsonb(x) order by company_id) from company_common_allowance_private.state x),'sessions',(select jsonb_agg(to_jsonb(x) order by id) from auth.sessions x)) v`);
 const before=await protectedData();
 const endpoint='http://127.0.0.1:38081';
 const secret='fixture-only-registered-labels-jwt-secret-00000000';
 const claims=(actor,role='authenticated',extra={})=>({role,sub:uid(actor),session_id:sid(actor),exp:Math.floor(Date.now()/1000)+600,...extra});
 const token=data=>{const head=Buffer.from(json({alg:'HS256',typ:'JWT'})).toString('base64url');const body=Buffer.from(json(data)).toString('base64url');return `${head}.${body}.${createHmac('sha256',secret).update(`${head}.${body}`).digest('base64url')}`;};
 phase='actual-postgrest-boundary';
 const name='registered-labels-'+randomUUID();
 container=name;
 await run('docker',['run','-d','--rm','--network','host','--name',name,'-e',`PGRST_DB_URI=postgresql://fixture_authenticator:fixture-only@127.0.0.1:5432/sko_registered_allowance_labels_fixture`,'-e','PGRST_DB_SCHEMAS=public','-e','PGRST_DB_ANON_ROLE=anon','-e',`PGRST_JWT_SECRET=${secret}`,'-e','PGRST_SERVER_PORT=38081','postgrest/postgrest:v13.0.7'],{timeout:120000,maxBuffer:1024*1024});
 let ready=false;
 for(let i=0;i<100;i++){
  try{const response=await fetch(endpoint+'/');if(response.ok){ready=true;break;}}catch{}
  await new Promise(resolve=>setTimeout(resolve,100));
 }
 assert.ok(ready,'local PostgREST ready');
 async function api(data,company=cid,expected=200){
  const headers={'Content-Type':'application/json'};if(data)headers.Authorization='Bearer '+token(data);
  const response=await fetch(endpoint+'/rpc/read_company_registered_allowance_labels',{method:'POST',headers,body:json({p_company_id:company})});
  const value=await response.json();equal(response.status,expected,'RPC status');return value;
 }
 const owner=await api(claims(1));const member=await api(claims(2));equal(member,owner,'ordinary same-company member gets the same price-free definitions');
 equal(owner.company_id,cid);equal(owner.registration_scope,'current');equal(owner.source_versions,{legacy_version:2,common_version:3});equal(owner.items.length,11);
 equal(owner.items.filter(x=>x.origin==='company_legacy').map(x=>[x.name,x.unit,x.display_unit]),[['旧登録A','day','回'],['旧登録B','day','件']]);
 equal(new Set(owner.items.filter(x=>x.origin==='company_common').map(x=>x.unit)),new Set(['hour','day','month']));
 equal(new Set(owner.items.filter(x=>x.origin==='company_common').map(x=>x.payroll_type)),new Set(['daily','hourly','monthly']));
 const forbidden=new Set(['amount_yen','rate_yen','salary','created_by','updated_by','tax_rate','welfare_rate']);
 const walk=x=>{if(x&&typeof x==='object')for(const[k,v]of Object.entries(x)){assert.ok(!forbidden.has(k),'no monetary/private key');walk(v);}};walk(owner);checks++;
 equal(json(owner).includes('87654321'),false);equal(json(owner).includes('OTHER-COMPANY-NAME'),false);equal(json(owner).includes('RETIRED-NAME'),false);
 await api(null,cid,401);await api(claims(1,'service_role'),cid,403);await api(claims(3),cid,403);
 await api(claims(1),other,403);await api(claims(1),'10000000-0000-0000-0000-000000000099',403);
 for(const actor of [4,5,6,7])await api(claims(actor),cid,403);
 await api(claims(8,'authenticated',{is_anonymous:true}),cid,403);
 equal(await protectedData(),before,'reader has no data/activation/session side effects');
 phase='legacy-unadopted-remains-visible-without-fabricated-identity';
 await db.query('delete from company_allowance_identity_private.identities where company_id=$1',[cid]);
 await db.query('delete from company_allowance_identity_private.state where company_id=$1',[cid]);
 const unadopted=await api(claims(2));
 equal(unadopted.items.filter(x=>x.origin==='company_legacy').map(x=>[x.name,x.id,x.generation,x.registration_version]),[['旧登録A',null,null,null],['旧登録B',null,null,null]]);
 equal(unadopted.source_versions.legacy_version,null);
 equal(unadopted.items.filter(x=>x.origin==='company_common').length,9);
 console.log(json({pass:true,checks,native_postgres:true,actual_local_postgrest:true,existing_session_source_pinned:true,
  same_company_member_read:true,cross_company_and_stale_session_denied:true,all_legacy_and_common_names:true,
  monetary_values_returned:false,activation_performed:false,synthetic_auth_surroundings:true,real_gotrue_exercised:false,production_changed:false,
  sql_sha256:createHash('sha256').update(unit).digest('hex')}));
}catch(error){console.error(json({pass:false,phase,message:String(error.message).slice(0,350),production_changed:false}));process.exitCode=1;}
finally{if(container)try{await run('docker',['rm','-f',container]);}catch{}if(db)await db.end();}
