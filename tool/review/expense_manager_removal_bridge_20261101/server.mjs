import http from 'node:http';
import assert from 'node:assert/strict';
import {prepare,info} from './fixture.mjs';
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
assert.equal(typeof Client,'function');
const {config,admin}=await prepare(Client);const trace=[];let dropped=false;
const routes={
 expense_manager_removal_workspace:{keys:['p_company','p_month'],sql:'select public.expense_manager_removal_workspace($1,$2) value'},
 expense_manager_remove:{keys:['p_command','p_company','p_claim','p_revision','p_session','p_reason'],sql:'select public.expense_manager_remove($1,$2,$3,$4,$5,$6) value'},
 expense_manager_removal_result:{keys:['p_command','p_company'],sql:'select public.expense_manager_removal_result($1,$2) value'},
 expense_manager_removal_notice:{keys:['p_notification'],sql:'select public.expense_manager_removal_notice($1) value'},
};
function reply(res,status,value){res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));}
const server=http.createServer(async(req,res)=>{
 let client;
 try{
  if(req.socket.remoteAddress!=='127.0.0.1')throw Error('loopback only');
  if(req.url==='/bridge-info' && req.method==='GET'){
   const counts=(await admin.query('select (select count(*) from private.expense_manager_removals)::int removals,(select count(*) from app_notifications)::int notices')).rows[0];
   const original=(await admin.query('select amount_yen,receipt_object_path,withdrawn,revision from private.expense_claims where id=$1',[info.claim])).rows[0];
   return reply(res,200,{...info,...counts,original,trace,synthetic_auth:true,deployable:false});
  }
  const match=/^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(req.url??'');const route=match&&routes[match[1]];
  if(req.method!=='POST' || !route)return reply(res,404,{code:'FIXTURE_ROUTE',message:'unavailable'});
  if(req.headers.apikey!=='fixture-only' || req.headers.authorization!=='Bearer fixture-only')return reply(res,403,{code:'FIXTURE_AUTH',message:'synthetic fixture credentials required'});
  const who=req.headers['x-fixture-actor'];if(!['manager','applicant'].includes(who))throw Error('actor');
  let body='';for await(const chunk of req){body+=chunk;if(Buffer.byteLength(body)>8192)throw Error('body size');}
  const params=JSON.parse(body);if(!params || Array.isArray(params) || typeof params!=='object' || Object.keys(params).length!==route.keys.length || !route.keys.every(k=>Object.hasOwn(params,k)))throw Error('exact body required');
  for(const key of route.keys){
   const value=params[key];
   if(key==='p_revision'){if(!Number.isInteger(value)||value<1)throw Error('revision');}
   else if(key==='p_reason'){if(typeof value!=='string'||!value.trim()||value!==value.trim()||value.length>1000)throw Error('reason');}
   else if(key==='p_month'){if(typeof value!=='string'||!/^\d{4}-\d{2}-01$/.test(value))throw Error('month');}
   else if(typeof value!=='string'||!/^00000000-0000-0000-0000-[0-9a-f]{12}$/.test(value) && key!=='p_command' && key!=='p_notification')throw Error('fixture identity');
   else if(['p_command','p_notification'].includes(key)&&!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(value))throw Error('uuid');
  }
  if(params.p_company!==undefined && params.p_company!==info.company)throw Error('fixture company');
  if(params.p_claim!==undefined && params.p_claim!==info.claim)throw Error('fixture claim');
  if(params.p_session!==undefined && params.p_session!==info.sid)throw Error('fixture SID');
  client=new Client({...config,application_name:'expense-bridge-'+who});await client.connect();
  await client.query('begin');await client.query('set local role authenticated');
  const actor=who==='manager'?info.manager:info.applicant;const sid=who==='manager'?info.sid:info.applicantSid;
  await client.query("select set_config('test.uid',$1,true),set_config('test.sid',$2,true)",[actor,sid]);
  const current=(await client.query("select current_user role,auth.uid() actor,auth.jwt()->>'session_id' sid")).rows[0];
  assert.equal(current.role,'authenticated');assert.equal(current.actor,actor);assert.equal(current.sid,sid);
  const result=(await client.query(route.sql,route.keys.map(k=>params[k]))).rows[0].value;
  await client.query('commit');
  trace.push({rpc:match[1],actor:who,params,result});
  if(match[1]==='expense_manager_remove' && req.headers['x-fixture-unknown-first-delete-result']==='1' && !dropped){dropped=true;return reply(res,200,null);}
  return reply(res,200,result);
 }catch(error){if(client)await client.query('rollback').catch(()=>{});reply(res,400,{code:error.code??'FIXTURE_INVALID',message:error.message});}
 finally{if(client)await client.end();}
});
server.listen(55439,'127.0.0.1',()=>console.log('EXPENSE_BRIDGE_READY synthetic Auth; actual isolated PostgreSQL SQL; deployable:false'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>{admin.end().finally(()=>process.exit(0));}));
