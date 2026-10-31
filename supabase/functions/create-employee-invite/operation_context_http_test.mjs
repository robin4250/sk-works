import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import {stripTypeScriptTypes} from 'node:module';
import {spawnSync} from 'node:child_process';
import {actor,company,sid,token} from './operation_context_fixture.mjs';

const worker='40000000-0000-0000-0000-000000000001';
const authUser='50000000-0000-0000-0000-000000000001';
const invite='70000000-0000-0000-0000-000000000001';
const sqlMode=process.env.SKO_INVITE_NATIVE_FIXTURE==='1';
function sql(query, allowFailure=false) {
 assert.equal(sqlMode,true);
 assert.equal(process.env.PGDATABASE,'invite_fixture');
 assert.ok(['127.0.0.1','localhost'].includes(process.env.PGHOST));
 const r=spawnSync(process.env.PSQL??'psql',['-XAtq','-v','ON_ERROR_STOP=1'],{input:query,encoding:'utf8',env:process.env});
 if(!allowFailure)assert.equal(r.status,0,r.stderr);
 return r;
}
const prefix=account=>`set role service_role; set request.jwt.claims='${JSON.stringify({role:'service_role'})}'; set sko.fixture.account='${account}'; `;
const contextSQL=(account='true')=>prefix(account)+`select public.employee_invite_operation_context('${actor}','${sid}','${company}')::text;`;

test('actual HTTP handler binds selected company/live SID and never exposes uncertain credentials',async()=>{
 const originalFetch=globalThis.fetch,originalDeno=globalThis.Deno,originalError=console.error;
 const logs=[],calls=[];let handler,scenario='ok',contextCalls=0,issued=0,memberRole='owner',storedWorker=null,storedInvite=null;
 const ownAuthDeletes=[];
 if(sqlMode){
  sql(`create schema auth;create schema private;
   do $$begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
   if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
   if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;end$$;
   create table auth.users(id uuid primary key,is_anonymous boolean,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
   create table public.company_members(company_id uuid,user_id uuid,role text);
   create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
   create function public.account_server_access_allowed(uuid) returns boolean language sql stable as $$select nullif(current_setting('sko.fixture.account',true),'')::boolean$$;
   grant usage on schema private to service_role;
   insert into auth.users values('${actor}',false,null);
   insert into auth.sessions values('${sid}','${actor}',null);
   insert into public.company_members values('${company}','${actor}','owner');`);
  const installer=fs.readFileSync(new URL('../../../tool/staged/employee_invite_context.sql.review-only',import.meta.url),'utf8');
  const hash=sql("select md5(pg_get_functiondef('public.account_server_access_allowed(uuid)'::regprocedure));").stdout.trim();
  sql(`set sko.review.invite_baseline='${hash}';\n`+installer);
  for(const account of ['false',''])assert.notEqual(sql(contextSQL(account),true).status,0,'false and NULL deny');
  assert.equal(JSON.parse(sql(contextSQL()).stdout.trim()).role,'owner');
  for(const role of ['anon','authenticated']){
   assert.notEqual(sql(`set role ${role};select public.employee_invite_operation_context('${actor}','${sid}','${company}');`,true).status,0);
  }
  const acl=JSON.parse(sql(`select json_build_object('public',has_function_privilege('service_role','public.employee_invite_operation_context(uuid,uuid,uuid)','execute'),'auth',has_function_privilege('authenticated','public.employee_invite_operation_context(uuid,uuid,uuid)','execute'),'anon',has_function_privilege('anon','public.employee_invite_operation_context(uuid,uuid,uuid)','execute'));`).stdout.trim());
  assert.deepEqual(acl,{public:true,auth:false,anon:false});
 }
 const upstream=http.createServer(async(req,res)=>{
  let raw='';for await(const chunk of req)raw+=chunk;const body=raw?JSON.parse(raw):{};
  const url=new URL(req.url,'http://fixture.invalid'),path=url.pathname;
  calls.push({path,method:req.method});
  const reply=(value,status=200)=>{res.writeHead(status,{'content-type':'application/json'});res.end(JSON.stringify(value));};
  if(path==='/auth/v1/user')return reply({id:actor});
  if(path==='/rest/v1/rpc/account_server_access_allowed')return reply(true);
  if(path==='/rest/v1/rpc/employee_invite_operation_context'){
   contextCalls++;
   assert.deepEqual(body,{p_actor:actor,p_session:sid,p_company:company});
   if(scenario==='unavailable'||scenario==='post-revoked'&&contextCalls>=3)return reply({error:'context denied'},403);
   if(sqlMode){
    const account=scenario==='null-access'?'':scenario==='false-access'?'false':'true';
    const r=sql(contextSQL(account),true);if(r.status!==0)return reply({error:'context denied'},403);
    return reply(JSON.parse(r.stdout.trim()));
   }
   if(['null-access','false-access'].includes(scenario))return reply({error:'context denied'},403);
   return reply({version:1,actor_id:actor,session_id:sid,company_id:company,role:scenario==='bad-role'?'unknown':scenario==='role-revoked'&&contextCalls>=2?'manager':memberRole});
  }
  if(path==='/auth/v1/settings')return reply({external:{phone:true}});
  if(path==='/rest/v1/rpc/begin_account_server_activity')return reply('20000000-0000-0000-0000-000000000001');
  if(path==='/rest/v1/rpc/finish_account_server_activity')return reply(true);
  if(path==='/auth/v1/admin/users'&&req.method==='POST'){
   issued++;
   if(scenario==='phone-during-auth')storedWorker.phone='08000000000';
   if(scenario==='linked-during-auth')storedWorker.user_id='60000000-0000-0000-0000-000000000001';
   if(scenario==='company-during-auth')storedWorker.company_id=worker;
   return reply({id:authUser});
  }
  if(path==='/auth/v1/admin/users/'+authUser&&req.method==='DELETE'){ownAuthDeletes.push(authUser);return reply({});} 
  if(path==='/rest/v1/employee_registration_invites'){
   if(req.method==='POST'){
    storedInvite={id:invite,...body};
    if(scenario==='phone-after-link')storedWorker.phone='08000000000';
    if(scenario==='invite-commit-ack-loss'){req.socket.destroy();return;}
    return reply([{id:invite}]);
   }
   return reply(url.searchParams.has('auth_user_id')&&storedInvite?.auth_user_id===authUser?[storedInvite]:[]);
  }
  if(path==='/rest/v1/workers'){
   const matches=()=>storedWorker&&[...url.searchParams].every(([key,value])=>
    ['select','limit'].includes(key)||value==='is.null'&&storedWorker[key]==null||value.startsWith('eq.')&&String(storedWorker[key])===value.slice(3));
   if(req.method==='GET')return reply(matches()?[storedWorker]:[]);
   if(req.method==='PATCH'){
    if(!matches())return reply([]);
    Object.assign(storedWorker,body);
    if(scenario==='patch-commit-ack-loss'){req.socket.destroy();return;}
    return reply([{id:worker}]);
   }
   if(req.method==='POST'){
    storedWorker={id:worker,...body};
    if(scenario==='post-commit-ack-loss'){req.socket.destroy();return;}
    return reply([{id:worker}]);
   }
   return reply({error:'destructive worker cleanup forbidden'},500);
  }
  if(path==='/rest/v1/companies')return reply([{employee_testflight_url:''}]);
  return reply({},404);
 });
 await new Promise(r=>upstream.listen(0,'127.0.0.1',r));
 const origin=`http://127.0.0.1:${upstream.address().port}`;
 globalThis.fetch=(url,options)=>{if(scenario==='sms-throw'&&String(url).endsWith('/sms-fixture'))throw Error('synthetic-private-upstream-error');return originalFetch(url,options);};
 globalThis.Deno={env:{get:name=>({SUPABASE_URL:origin,SUPABASE_SERVICE_ROLE_KEY:'synthetic-service-key',SKO_EMPLOYEE_INVITE_SMS_WEBHOOK:origin+'/sms-fixture',SKO_TESTFLIGHT_URL:'https://fixture.invalid/distribution'}[name])},serve:value=>{handler=value;}};
 console.error=(...args)=>logs.push(args);
 const sourceUrl=new URL('./index.ts',import.meta.url);
 const source=fs.readFileSync(sourceUrl,'utf8').replace('import "jsr:@supabase/functions-js/edge-runtime.d.ts";','')
  .replace(/from '([^']+\.mjs)'/g,(_,p)=>'from '+JSON.stringify(new URL(p,sourceUrl).href));
 const incoming=http.createServer(async(req,res)=>{
  let body='';for await(const chunk of req)body+=chunk;
  try{const response=await handler(new Request(origin+'/incoming',{method:'POST',headers:req.headers,body}));
   res.writeHead(response.status,{'content-type':'application/json'});res.end(await response.text());}
  catch{res.writeHead(500);res.end('{}');}
 });
 try{
  await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source,{mode:'strip'})).toString('base64'));
  await new Promise(r=>setImmediate(r));logs.length=0;
  await new Promise(r=>incoming.listen(0,'127.0.0.1',r));
  const endpoint=`http://127.0.0.1:${incoming.address().port}/`;
  const send=payload=>{storedInvite=null;storedWorker={id:worker,company_id:company,affiliation:'employee',name:'Synthetic',phone:'07000000000',user_id:null,status:'inactive'};return originalFetch(endpoint,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify({name:'Synthetic',phone:'07000000000',companyId:company,sessionId:sid,...payload})});};
  for(const payload of [{companyId:undefined},{sessionId:undefined},{sessionId:worker},{companyId:'not-uuid'}]){
   calls.length=0;issued=0;const response=await send(payload);assert.equal(response.status,403);assert.equal(issued,0);
   assert.equal(calls.some(c=>c.path.includes('employee_invite_operation_context')),false);
  }
  for(scenario of ['unavailable','null-access','false-access','bad-role']){
   if(sqlMode&&scenario==='bad-role')continue;
   calls.length=0;contextCalls=0;issued=0;const response=await send({});assert.equal(response.status,503);
   assert.equal(issued,0);assert.equal(calls.some(c=>c.path==='/auth/v1/settings'),false);
  }
  if(sqlMode){
   for(const change of [
    `update auth.sessions set not_after=clock_timestamp()-interval '1 second'`,
    `update auth.sessions set user_id='${worker}'`,
    `delete from public.company_members`,
    `update public.company_members set role='unknown'`,
    `update auth.users set is_anonymous=true`,
    `update auth.users set banned_until=clock_timestamp()+interval '1 day'`,
   ]){
    sql(change);scenario='ok';contextCalls=0;issued=0;
    assert.equal((await send({})).status,503);assert.equal(issued,0);
    sql(`update auth.sessions set user_id='${actor}',not_after=null;update auth.users set is_anonymous=false,banned_until=null;delete from public.company_members;insert into public.company_members values('${company}','${actor}','owner');`);
   }
  }
  scenario='ok';contextCalls=0;issued=0;
  assert.equal((await send({workerId:worker,expectedPhone:'08000000000'})).status,409);assert.equal(issued,0);
  for(memberRole of ['owner','admin','manager','viewer']) {
   if(sqlMode)sql(`update public.company_members set role='${memberRole}'`);
   contextCalls=0;issued=0;
   const status=(await send({requestedRole:'manager'})).status;
   assert.equal(status,['owner','admin'].includes(memberRole)?200:403);assert.equal(issued,['owner','admin'].includes(memberRole)?1:0);
  }
  memberRole='owner';if(sqlMode)sql("update public.company_members set role='owner'");
  if(!sqlMode){scenario='role-revoked';contextCalls=0;issued=0;assert.equal((await send({})).status,403);assert.equal(issued,0);}
  for(scenario of ['phone-during-auth','linked-during-auth','company-during-auth']){
   contextCalls=0;issued=0;ownAuthDeletes.length=0;logs.length=0;
   const response=await send({workerId:worker,expectedPhone:'07000000000'});
   assert.equal(response.status,409);assert.equal((await response.json()).code,'invite_result_unknown');
   assert.equal(storedInvite,null);assert.equal(issued,1);
   assert.deepEqual(ownAuthDeletes,[authUser],'only own unreferenced Auth from CAS-zero is removed');
   if(scenario==='linked-during-auth')assert.equal(storedWorker.user_id,'60000000-0000-0000-0000-000000000001');
   if(scenario==='phone-during-auth')assert.equal(storedWorker.phone,'08000000000');
   if(scenario==='company-during-auth')assert.equal(storedWorker.company_id,worker);
  }
  for(scenario of ['patch-commit-ack-loss','post-commit-ack-loss','invite-commit-ack-loss','phone-after-link']){
   contextCalls=0;issued=0;ownAuthDeletes.length=0;logs.length=0;
   const response=await send(scenario==='patch-commit-ack-loss'?{workerId:worker,expectedPhone:'07000000000'}:{});
   assert.equal(response.status,409);const out=await response.json();assert.equal(out.code,'invite_result_unknown');
   assert.equal('temporaryPassword'in out,false);assert.equal('qrPayload'in out,false);
   assert.equal(storedWorker.user_id,authUser);assert.deepEqual(ownAuthDeletes,[],'committed worker/Auth are preserved after lost ACK');
   if(scenario==='invite-commit-ack-loss')assert.equal(storedInvite.auth_user_id,authUser);
   assert.equal(issued,1);
  }
  logs.length=0;
  scenario='post-revoked';contextCalls=0;issued=0;
  let response=await send({});assert.equal(response.status,409);assert.equal(issued,1);
  let value=await response.json();assert.equal(value.code,'invite_result_unknown');
  assert.equal('temporaryPassword'in value,false);assert.equal('qrPayload'in value,false);
  scenario='ok';contextCalls=0;issued=0;
  response=await send({});assert.equal(response.status,200);value=await response.json();
  assert.equal(value.companyId,company);assert.equal(value.sessionId,sid);assert.equal(value.actorId,actor);
  assert.equal(value.workerId,worker);assert.equal(value.authUserId,authUser);
  const qr=JSON.parse(value.qrPayload);assert.equal(qr.inviteId,value.inviteId);assert.equal(qr.password,value.temporaryPassword);
  assert.equal(issued,1);assert.equal(contextCalls,4);assert.deepEqual(logs,[]);
  scenario='sms-throw';contextCalls=0;issued=0;
  response=await send({deliverSms:true});assert.equal(response.status,200);
  value=await response.json();assert.equal(value.smsSent,false);
  assert.deepEqual(logs,[['employee invite sms delivery failed']]);
  assert.equal(JSON.stringify(logs).includes('synthetic-private-upstream-error'),false);
 }finally{
  globalThis.fetch=originalFetch;globalThis.Deno=originalDeno;console.error=originalError;
  await new Promise(r=>incoming.close(r));await new Promise(r=>upstream.close(r));
 }
});
