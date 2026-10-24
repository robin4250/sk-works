// Disposable local GoTrue/PostgREST only; never accepts a hosted endpoint.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,createHash} from 'node:crypto';
const run=promisify(execFile),root=process.cwd();
const parent=path.resolve(process.env.RUNNER_TEMP??'');
if(!process.env.CI||!process.env.RUNNER_TEMP||parent==='/'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('Isolated CI without hosted credentials required');
const project='sko-checkout-real-jwt-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const read=p=>fs.readFile(path.join(root,p),'utf8');
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let phase='setup',db,started=false,owns=false,lastHttp;
let checks=0;const eq=(a,b)=>{assert.deepEqual(a,b);checks++;};
try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owns=true;
 await cli(['init']);
 const configPath=path.join(workdir,'supabase/config.toml');
 let config=await fs.readFile(configPath,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`);
 for(const [a,b] of [['54321','53981'],['54322','53982'],['54320','53980'],['54323','53983'],['54324','53984'],['54327','53987'],['54329','53989']])config=config.replaceAll(a,b);
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');
 config=config.replace(/^jwt_expiry = .*$/m,'jwt_expiry = 60');
 await fs.writeFile(configPath,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='local-stack';started=true;
 // CLI output contains local keys and is deliberately never printed.
 await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout);
 const api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53981');
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(database.hostname)&&database.port==='53982'&&database.pathname==='/postgres');
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
 const users={},sessions={};
 const password='fixture-'+randomBytes(20).toString('hex')+'!A1';
 for(const name of ['owner','othercompany','outsider','revoked']){
  const created=await request('/auth/v1/admin/users',{service:true,body:{email:name+'@example.invalid',password,email_confirm:true}});eq(created.status,200);users[name]=await created.json();
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});eq(login.status,200);sessions[name]=await login.json();
  const claims=JSON.parse(Buffer.from(sessions[name].access_token.split('.')[1],'base64url').toString('utf8'));
  eq(claims.sub,users[name].id);assert.ok(claims.session_id);
  eq((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
 }
 phase='unchanged-checkout-foundation';
 let foundation=await read('tool/fixtures/company_checkout_foundation.sql');
 for(const exact of ['create role anon;','create role authenticated;','create role service_role bypassrls;','create schema auth;',"create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;"]){eq(foundation.split(exact).length,2);foundation=foundation.replace(exact,'');}
 assert.ok(!/\b(?:insert\s+into|update|delete\s+from|truncate(?:\s+table)?)\s+auth\./i.test(foundation));await db.query(foundation);
 await db.query('create table private.account_deletion_access_restrictions(user_id uuid primary key)');
 const predicate=JSON.parse(await read('tool/fixtures/company_checkout_account_predicate.json'));
 await db.query(predicate.definition);eq((await db.query('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[predicate.signature])).rows[0].v,predicate.body_md5);
 const body=definition=>{const m=/\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$/i.exec(definition);assert.ok(m);return m[2];};
 const fq=s=>s.split('(')[0].includes('.')?s:'public.'+s;
 const fixture=JSON.parse(await read('tool/fixtures/company_checkout_actual_sources.json'));
 for(const item of [...fixture.functions].sort((a,b)=>Number(/LANGUAGE sql/i.test(a.definition))-Number(/LANGUAGE sql/i.test(b.definition)))){
  eq(createHash('md5').update(body(item.definition)).digest('hex'),item.source_md5);await db.query(item.definition);
  await db.query(`revoke all on function ${fq(item.signature)} from public,anon,authenticated,service_role`);
  if(fq(item.signature).startsWith('public.')||item.signature==='private.save_daily_report_signature(uuid,text,text,jsonb)')await db.query(`grant execute on function ${fq(item.signature)} to authenticated`);
 }
 await db.query('grant usage on schema public,private to authenticated');
 const install=path.join(workdir,'checkout.sql'),manifest=path.join(workdir,'checkout.json');
 await run('python3',['tool/prepare_company_checkout_integration.py','--output',install,'--manifest',manifest]);
 await db.query(await fs.readFile(install,'utf8'));await db.query(await read('docs/candidates/company_checkout_eligibility.sql.review-only'));
 await db.query(`create trigger attendance_refresh_payroll after insert or update or delete on public.attendance_entries for each row execute function private.attendance_refresh_payroll();
 create trigger zz_attendance_sync_payroll_detail after insert or update or delete on public.attendance_entries for each row execute function private.attendance_sync_payroll_detail();
 create trigger payroll_custom_money before insert or update on public.payroll_statements for each row execute function private.apply_payroll_custom_money();`);
 const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const A=id(1),B=id(2),W=id(20),W2=id(21),SITE=id(30),SITE2=id(31),LEGACY=id(100);
 await db.query('insert into companies(id) values($1),($2)',[A,B]);
 await db.query('insert into company_members(company_id,user_id) values($1,$2),($3,$4),($1,$5)',[A,users.owner.id,B,users.othercompany.id,users.revoked.id]);
 await db.query("insert into workers(id,company_id,name) values($1,$2,'JWT fixture worker'),($3,$4,'JWT other worker')",[W,A,W2,B]);
 await db.query('insert into sites(id,company_id) values($1,$2),($3,$4)',[SITE,A,SITE2,B]);
 await db.query("insert into worker_payroll_settings(company_id,worker_id,allowance_name_1,allowance_1) values($1,$2,'JWT会社手当',1700)",[A,W]);
 await db.query("insert into company_rate_settings(company_id,allowance_1_name,allowance_1_amount_yen,allowance_1_unit) values($1,'JWT会社手当',3000,'回')",[A]);
 await db.query('insert into company_allowance_identity_private.state values($1,1)',[A]);
 await db.query('insert into company_allowance_identity_private.identities(id,company_id,slot,generation) values($1,$2,1,1)',[LEGACY,A]);
 const selection={contract_version:1,items:[{origin:'company_legacy',id:LEGACY,generation:1,registration_version:1,name_snapshot:'JWT会社手当',unit:'day'}]};
 const workers=[{worker_id:W,allowance_label:'JWT会社手当',allowance_amount:0,work_category:'day',company_allowance_selections:selection}];
 const owner=sessions.owner.access_token;
 const ownerSession=JSON.parse(Buffer.from(owner.split('.')[1],'base64url').toString('utf8')).session_id;
 const draftBody={p_report_id:null,p_site_id:SITE,p_route_assignment_id:null,p_report_date:'2020-10-20',p_work_description:'JWT正規日報',p_workers:workers};
 await db.query(`grant select on public.daily_reports,public.daily_report_workers,public.company_members,public.attendance_entries to authenticated;
 grant update on public.daily_report_workers,public.attendance_entries to authenticated;
 alter table public.attendance_entries enable row level security;
 create policy fixture_attendance_scope on public.attendance_entries to authenticated using(exists(select 1 from public.company_members m where m.company_id=attendance_entries.company_id and m.user_id=auth.uid())) with check(exists(select 1 from public.company_members m where m.company_id=attendance_entries.company_id and m.user_id=auth.uid()));
 alter table public.daily_reports enable row level security;alter table public.daily_report_workers enable row level security;
 create policy fixture_report_scope on public.daily_reports to authenticated using(exists(select 1 from public.company_members m where m.company_id=daily_reports.company_id and m.user_id=auth.uid()));
 create policy fixture_worker_scope on public.daily_report_workers to authenticated using(exists(select 1 from public.daily_reports r where r.id=report_id));
 notify pgrst,'reload schema';`);
 await new Promise(resolve=>setTimeout(resolve,1000));
 phase='real-jwt-public-draft-and-eligibility';
 let response=await rpc('save_daily_report_destination_draft',draftBody,owner);eq(response.status,200);const report=await response.json();
 response=await request('/rest/v1/daily_report_workers?report_id=eq.'+report+'&select=worker_id,company_allowance_selections',{method:'GET',token:owner});eq(response.status,200);eq((await response.json())[0].company_allowance_selections,selection);
 const eligible=()=>rpc('read_daily_report_company_allowance_eligibility',{p_report_id:report},owner);
 response=await eligible();eq(response.status,200);eq((await response.json()).workers[0].items[0].id,LEGACY);
 for(const name of ['othercompany','outsider']){response=await rpc('read_daily_report_company_allowance_eligibility',{p_report_id:report},sessions[name].access_token);assert.ok(response.status>=400&&response.status<500);checks++;}
 response=await rpc('save_daily_report_destination_draft',{...draftBody,p_workers:[{...workers[0],worker_id:W2}]},owner);assert.ok(response.status>=400);checks++;
 response=await rpc('save_daily_report_destination_draft',{...draftBody,p_workers:[{...workers[0],company_allowance_selections:{...selection,items:[{...selection.items[0],rate_yen:99999}]}}]},owner);assert.ok(response.status>=400);checks++;
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.owner.id]);
 response=await eligible();assert.ok(response.status>=400);checks++;
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.owner.id]);
 eq((await db.query('select count(*)::int n from company_checkout_allowance_private.receipts')).rows[0].n,0);
 phase='real-jwt-two-signature-and-private-receipt';
 const signature={strokes:[[{x:0.1,y:0.1}]]};
 for(const name of ['othercompany','outsider']){response=await rpc('save_daily_report_signature',{p_report_id:report,p_role:'representative',p_signer_name:'wrong actor',p_signature_json:signature},sessions[name].access_token);assert.ok(response.status>=400);checks++;}
 response=await rpc('sign_daily_report',{p_report_id:report,p_signer_name:'bypass',p_signature_json:signature},owner);assert.ok(response.status>=400);checks++;
 response=await rpc('save_daily_report_signature',{p_report_id:report,p_role:'representative',p_signer_name:'JWT代表',p_signature_json:signature},owner);assert.ok([200,204].includes(response.status));checks++;
 eq((await db.query('select count(*)::int n from company_checkout_allowance_private.receipts')).rows[0].n,0);
 response=await rpc('save_daily_report_signature',{p_report_id:report,p_role:'supervisor',p_signer_name:'JWT責任',p_signature_json:signature},owner);assert.ok([200,204].includes(response.status));checks++;
 eq((await db.query('select count(*)::int n from company_checkout_allowance_private.receipts')).rows[0].n,1);
 eq((await db.query('select gross_pay v from payroll_statements where worker_id=$1',[W])).rows[0].v,13000);
 eq((await db.query('select captured_by v from company_checkout_allowance_private.receipts')).rows[0].v,users.owner.id);
 response=await request('/rest/v1/daily_report_workers?report_id=eq.'+report,{method:'PATCH',token:owner,body:{company_allowance_selections:null}});assert.ok(response.status>=400);checks++;
 response=await request('/rest/v1/attendance_entries?source_report_id=eq.'+report,{method:'PATCH',token:owner,body:{company_allowance_receipt_id:null}});assert.ok(response.status>=400);checks++;
 eq((await db.query('select count(*)::int n from attendance_entries where source_report_id=$1 and company_allowance_receipt_id is not null',[report])).rows[0].n,1);
 response=await request('/rest/v1/receipts?select=*',{method:'GET',token:owner});assert.ok(response.status>=400);checks++;
 eq((await db.query("select has_schema_privilege('authenticated','company_checkout_allowance_private','USAGE') v")).rows[0].v,false);
 eq((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[ownerSession,users.owner.id])).rows[0].n,1);
 response=await request('/auth/v1/user',{method:'GET',token:owner});eq(response.status,200);eq((await response.json()).id,users.owner.id);
 phase='real-jwt-expiry-and-revocation-observation';
 response=await rpc('save_daily_report_destination_draft',{...draftBody,p_report_date:'2020-10-21'},owner);eq(response.status,200);const expiryReport=await response.json();
 response=await rpc('read_daily_report_company_allowance_eligibility',{p_report_id:expiryReport},sessions.revoked.access_token);eq(response.status,200);
 response=await request('/auth/v1/logout?scope=global',{token:sessions.revoked.access_token});assert.ok(response.status===204||response.status===200);checks++;
 const revokedClaims=JSON.parse(Buffer.from(sessions.revoked.access_token.split('.')[1],'base64url').toString('utf8'));
 eq((await db.query('select count(*)::int n from auth.sessions where id=$1',[revokedClaims.session_id])).rows[0].n,0);
 response=await rpc('read_daily_report_company_allowance_eligibility',{p_report_id:expiryReport},sessions.revoked.access_token);
 assert.ok([200,401].includes(response.status));checks++;
 const revokedTokenAcceptedUntilExpiry=response.status===200;
 console.log(JSON.stringify({diagnostic:'real_jwt_session_revocation_boundary',session_removed:true,
  revoked_token_rpc_status:response.status,revoked_token_accepted_until_expiry:revokedTokenAcceptedUntilExpiry,
  real_uid_predicate_checks_session_id:false,production_changed:false}));
 const ownerClaims=JSON.parse(Buffer.from(owner.split('.')[1],'base64url').toString('utf8'));
 // PostgREST documents a 30-second JWT exp clock-skew allowance.
 // https://docs.postgrest.org/en/latest/references/auth.html#time-based-claims-validation
 const waitMs=Math.max(0,(ownerClaims.exp+32)*1000-Date.now());assert.ok(waitMs<125000);
 console.log('Waiting only for the isolated real owner JWT expiry; no production session affected');
 await new Promise(resolve=>setTimeout(resolve,waitMs));
 response=await rpc('read_daily_report_company_allowance_eligibility',{p_report_id:expiryReport},owner);eq(response.status,401);
 eq((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value,authUidBefore);
 console.log(JSON.stringify({pass:true,checks,real_gotrue:true,real_postgrest:true,real_token_expiry_denied:true,revoked_token_accepted_until_expiry:revokedTokenAcceptedUntilExpiry,session_revocation_proven:!revokedTokenAcceptedUntilExpiry,original_owner_session_preserved_before_expiry:true,source_bound_report_signature_receipt:true,private_prices_not_exposed:true,synthetic_application_rls:true,production_rls_proven:false,production_changed:false}));
}catch(error){console.error(JSON.stringify({pass:false,phase,code:error?.code??'ASSERTION',last_http:lastHttp,production_changed:false}));process.exitCode=1;}
finally{if(db)await db.end().catch(()=>{});if(started)await cli(['stop','--no-backup']).catch(()=>{process.exitCode=1;});if(owns)await fs.rm(workdir,{recursive:true,force:true});}
