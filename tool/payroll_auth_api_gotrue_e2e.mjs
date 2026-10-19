// Disposable local GoTrue/PostgREST only; never accepts a hosted endpoint.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes} from 'node:crypto';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(!process.env.CI||!process.env.RUNNER_TEMP||parent==='/'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Isolated CI without hosted credentials required');
const project='sko-payroll-auth-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const read=p=>fs.readFile(path.join(root,p),'utf8');
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let phase='setup',db,started=false,owns=false,lastHttp;
try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owns=true;
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');
 let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`);
 for(const [a,b] of [['54321','53961'],['54322','53962'],['54320','53960'],['54323','53963'],['54324','53964'],['54327','53967'],['54329','53969']])config=config.replaceAll(a,b);
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 await fs.writeFile(configPath,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='local-stack';started=true;
 // CLI output contains local keys and is deliberately never printed.
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53961');
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(database.hostname)&&database.port==='53962'&&database.pathname==='/postgres');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof publicKey,'string');assert.equal(typeof serviceKey,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 const authUidBefore=(await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value;
 async function request(route,{token,body,service=false,method='POST'}={}) {
  const url=new URL(route,api);assert.equal(url.origin,api.origin);
  const response=await fetch(url,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:service?serviceKey:publicKey,...(service&&!serviceKey.startsWith('sb_'+'secret_')?{Authorization:'Bearer '+serviceKey}:{}),...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
  lastHttp={route,status:response.status};return response;
 }
 const rpc=(name,body,token)=>request('/rest/v1/rpc/'+name,{body,token});
 const users={},tokens={},mapping=new Map();
 phase='real-local-auth';
 const password='fixture-'+randomBytes(20).toString('hex')+'!A1';
 for(const [index,name] of ['owner','editor','viewer','outsider','manager'].entries()) {
  const created=await request('/auth/v1/admin/users',{service:true,body:{email:name+'@example.invalid',password,email_confirm:true}});
  assert.equal(created.status,200);users[name]=await created.json();
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});
  assert.equal(login.status,200);const session=await login.json();tokens[name]=session.access_token;
  const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
  assert.equal(claims.sub,users[name].id);assert.ok(claims.session_id);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
  mapping.set('00000000-0000-0000-0000-00000000000'+(index+1),users[name].id);
 }
 const replace=s=>{for(const [a,b] of mapping)s=s.replaceAll(a,b);return s;};
 const params=value=>typeof value==='string'?replace(value):Array.isArray(value)?value.map(params):value;
 let adapted=false;
 const fixture={exec:async sql=>{
  if(sql.includes('-- Local isolated SQL harness:')) {
   assert.equal(adapted,false);adapted=true;
   for(const exact of ['create role anon; create role authenticated;','create schema auth;','create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting(\'request.jwt.claim.sub\',true),\'\')::uuid$$;','create table auth.users(id uuid primary key);',"insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004');"]) {
    assert.equal(sql.split(exact).length,2,'Known fixture Auth prerequisite changed');sql=sql.replace(exact,'');
   }
  }
  assert.ok(!/\b(?:insert\s+into|update|delete\s+from|truncate(?:\s+table)?)\s+auth\./i.test(sql),'App fixture cannot mutate GoTrue tables');
  return db.query(replace(sql));
 },query:(sql,values=[])=>db.query(replace(sql),values.map(params))};
 phase='unchanged-payroll-fixture';await setupPayrollScopeFixture(fixture);
 assert.equal(adapted,true);
 for(const name of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql','20261014033249_payroll_fixed_deduction_overrides.sql']) {phase='migration-'+name;await fixture.exec(await read('supabase/migrations/'+name));}
 phase='predicate-fixture-tables';
 await db.query('reset role');
 await db.query("select set_config('request.jwt.claim.sub','',false)");
 await db.query(`create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_view_admin_site_data boolean default false,can_manage_admin_site_data boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
 create table public.payroll_approvers(company_id uuid,user_id uuid,position integer);
 create table private.professional_invites(company_id uuid,claimed_by uuid,status text,payroll_access text);`);
 const predicates=JSON.parse(await read('tool/fixtures/payroll_auth_predicates_20261019.json'));
 assert.equal(predicates.format,'sko-payroll-auth-fixture-v1');assert.equal(predicates.functions.length,5);
 for(const f of predicates.functions)await db.query('alter function '+f.signature+' rename to synthetic_old_'+f.signature.split('.')[1].split('(')[0]);
 for(const f of predicates.functions) {
  phase='predicate-'+f.signature;
  await db.query(f.definition);
  await db.query('revoke all on function '+f.signature+' from public,anon;grant execute on function '+f.signature+' to authenticated');
  const actual=(await db.query('select md5(prosrc) body_md5,prosecdef,provolatile,proconfig from pg_proc where oid=to_regprocedure($1)',[f.signature])).rows[0];
  for(const key of ['body_md5','prosecdef','provolatile','proconfig'])assert.deepEqual(actual[key],f[key],'Predicate attribute '+key);
 }
 const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
 await db.query('insert into public.company_members values($1,$2,\'manager\')',[cid,users.manager.id]);
 phase='stale-draft-fixture';
 await db.query(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;delete from public.paid_leave_requests;
 update public.worker_payroll_settings set pay_type='daily',day_daily=20000,custom_earnings='[]',custom_deductions='[]',family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0,other_deduction_monthly=0 where worker_id='${wid}';`);
 await db.query("insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days) values(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-12',null,1)",[cid,wid]);
 const row=async()=>(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];
 const original=await row();assert.ok(original,'Expected synthetic draft');assert.equal(original.gross_pay,0,'Expected stale NULL-category draft');
 phase='reviewed-candidates';
 await db.query(await read('supabase/migrations/20261018215043_fix_payroll_null_work_category.sql'));
 for(const file of ['payroll_single_draft_recalculation_20261019.sql.review-only','payroll_single_draft_preview_20261019.sql.review-only'])await db.query(await read('docs/candidates/'+file));
 const protectedBusiness=async()=>(await db.query(`select jsonb_build_object('salary',(select jsonb_agg(to_jsonb(x) order by id) from public.payroll_statements x),'audit',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.payroll_audit x),'attendance',(select jsonb_agg(to_jsonb(x) order by id) from public.attendance_entries x),'settings',(select jsonb_agg(to_jsonb(x) order by worker_id) from public.worker_payroll_settings x)) value`)).rows[0].value;
 const identity=async()=>(await db.query("select jsonb_build_object('users',(select jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'app_metadata',raw_app_meta_data) order by id) from auth.users),'identities',(select jsonb_agg(to_jsonb(i) order by id) from auth.identities i),'sessions',(select jsonb_agg(jsonb_build_object('id',id,'user_id',user_id) order by id) from auth.sessions)) value")).rows[0].value;
 const identityBefore=await identity(),before=await protectedBusiness();
 const scope={p_statement_id:original.id,p_expected_revision:original.revision,p_company_id:cid,p_worker_id:wid,p_period_start:'2026-09-01'};
 const previewName='preview_one_payroll_draft',applyName='recalculate_one_payroll_draft';
 phase='postgrest-schema-cache';await db.query("notify pgrst,'reload schema'");
 for(let attempt=0;;attempt++) {
  const r=await rpc(previewName,scope,tokens.owner);if(r.status===200)break;
  const e=await r.json();if(e.code!=='PGRST202'||attempt===30)throw Error('Local schema cache unavailable');
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 phase='authenticated-preview';const response=await rpc(previewName,scope,tokens.editor);assert.equal(response.status,200);const preview=await response.json();
 assert.equal(preview.preview_kind,'current_draft_only');assert.equal(preview.before_value.id,original.id);assert.equal(preview.projected_calculation,null);
 assert.deepEqual(await protectedBusiness(),before);
 const apply={...scope,p_confirmed:true,p_expected_source:preview.expected_source};
 async function rejected(name,body,token,code='42501') {
  const r=await rpc(name,body,token);assert.notEqual(r.status,200);const error=await r.json();assert.equal(error.code,code);
  assert.deepEqual(await protectedBusiness(),before);
 }
 phase='denied-real-sessions';
 for(const role of ['viewer','outsider','manager']) {await rejected(previewName,scope,tokens[role]);await rejected(applyName,apply,tokens[role]);}
 for(const name of [previewName,applyName]) {const r=await rpc(name,name===previewName?scope:apply);assert.ok([401,403].includes(r.status));assert.deepEqual(await protectedBusiness(),before);}
 await rejected(applyName,{...apply,p_confirmed:false},tokens.editor,'22023');
 await rejected(applyName,{...apply,p_expected_revision:original.revision+1},tokens.editor,'40001');
 phase='live-app-permission-changes';await db.query('update public.payroll_access set can_edit=false where company_id=$1 and user_id=$2',[cid,users.editor.id]);
 await rejected(applyName,apply,tokens.editor);await db.query('update public.payroll_access set can_edit=true where company_id=$1 and user_id=$2',[cid,users.editor.id]);
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.editor.id]);
 await rejected(previewName,scope,tokens.editor);await rejected(applyName,apply,tokens.editor);await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.editor.id]);
 phase='authenticated-apply';const applied=await rpc(applyName,apply,tokens.editor);assert.equal(applied.status,200);const result=await applied.json();
 const fixed=await row();assert.equal(result.statement_id,original.id);assert.equal(result.finalized,false);assert.equal(fixed.gross_pay,20000);assert.equal(fixed.net_pay,20000);assert.equal(fixed.workflow_state,'draft');assert.equal(fixed.revision,original.revision+1);
 assert.equal((await db.query("select count(*)::int n from public.payroll_audit where statement_id=$1 and actor_id=$2 and action='automatic_recalculation'",[fixed.id,users.editor.id])).rows[0].n,1);
 assert.deepEqual(await identity(),identityBefore);
 assert.equal((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value,authUidBefore);
 console.log('PASS actual isolated GoTrue sessions -> PostgREST current-draft preview and exact-scope apply; original GoTrue Auth function and identity/session rows preserved');
 console.log('PASS owner/editor preview, viewer/other-company/ungranted-manager/anonymous refusals, live permission removal, restricted account, confirmation/revision rejection and unchanged business state on every refusal');
 console.log('PASS five frozen production-matching access predicate bodies/security attributes; successful synthetic recalculation remains draft and records the real isolated Auth actor');
 console.log('LIMIT: synthetic application tables and fixture grants; not production JWT/RLS/config/owner/ACL, OAuth/device testing, or a production deployment/recalculation');
} catch(error) {
 console.error('FAIL isolated payroll Auth phase='+phase+' code='+(typeof error?.code==='string'?error.code:'E2E_ASSERTION'));
 if(typeof error?.actual==='number'&&typeof error?.expected==='number')console.error(JSON.stringify({actual:error.actual,expected:error.expected}));
 const structural=Object.fromEntries(['schema','table','column','constraint','routine'].filter(k=>typeof error?.[k]==='string'&&/^[a-zA-Z_][a-zA-Z0-9_]{0,100}$/.test(error[k])).map(k=>[k,error[k]]));
 if(Object.keys(structural).length)console.error(JSON.stringify(structural));
 if(lastHttp)console.error(JSON.stringify(lastHttp));process.exitCode=1;
} finally {
 if(db)await db.end().catch(()=>{});
 if(started)await cli(['stop','--no-backup']).catch(()=>{console.error('Owned local fixture cleanup failed');process.exitCode=1;});
 if(owns)await fs.rm(workdir,{recursive:true,force:true});
}
