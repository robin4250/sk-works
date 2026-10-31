// Isolated synthetic catalog only. Never a production connection.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const native = process.env.SKO_COMPANY_LINK_NATIVE === '1';
const ids = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor='10000000-0000-0000-0000-000000000001', sid=ids(101), sid2=ids(102);
let db;let nativeClient;
(async()=>{
 if(native){
  assert.equal(process.env.PGHOST,'127.0.0.1');assert.equal(process.env.PGDATABASE,'company_link_fixture');
  const {Client}=require('pg');nativeClient=new Client();await nativeClient.connect();
  db={exec:s=>nativeClient.query(s),query:s=>nativeClient.query(s)};
 }else{const {PGlite}=require('@electric-sql/pglite');db=new PGlite();}
 // Reuse the unchanged existing synthetic company's full business schema.
 const legacyFixture=fs.readFileSync('tool/company_link_sql_test.cjs','utf8');
 const begin=legacyFixture.indexOf('await db.exec(`'),end=legacyFixture.indexOf('`);',begin);
 assert(begin>0&&end>begin);await db.exec(legacyFixture.slice(begin+15,end));
 const legacySql=fs.readFileSync('supabase/migrations/20261015005238_company_link_requests.sql','utf8');
 await db.exec(legacySql);
 await db.exec(`create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.jwt() returns jsonb language sql as $$select current_setting('test.jwt')::jsonb$$;
 grant usage on schema private,auth to authenticated;
 insert into auth.sessions values('${sid}','${actor}',null),('${sid2}','${actor}',null);
 insert into public.companies values('${ids(3)}','Gamma','C','3','333');
 insert into public.company_members values('${ids(2)}','${actor}','admin'),('${ids(3)}','${actor}','admin');`);
 const hashes=(await db.query(`select md5(pg_get_functiondef('private.account_access_allowed()'::regprocedure)) account,
  md5(pg_get_functiondef('private.attach_approved_trade_link(uuid,uuid,text)'::regprocedure)) attach`)).rows[0];
 // Hashes describe this synthetic fixture only; not the deployed catalog.
 await db.exec(`set sko.company_link_bound.baseline_account='${hashes.account}';set sko.company_link_bound.baseline_attach='${hashes.attach}';`);
 const candidate=fs.readFileSync('tool/staged/company_link_bound.sql.review-only','utf8');
 const legacySnapshot=async()=>(await db.query(`select p.oid::regprocedure::text signature,md5(pg_get_functiondef(p.oid)) body,p.proacl::text acl
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('private','public') and p.proname in('trade_link_company_admin_id','trade_company_link_workspace',
 'set_trade_company_link_enabled','search_trade_company_links','request_trade_company_link','respond_trade_company_link','attach_approved_trade_link') order by 1`)).rows;
 const originalLegacy=await legacySnapshot();
 await db.exec('create role unexpected_fixture_role;alter default privileges grant execute on functions to unexpected_fixture_role;');
 await assert.rejects(db.exec(candidate),/ownership or ACL/);await db.exec('rollback;');
 assert.equal((await db.query("select to_regclass('private.company_link_bound_operations') object")).rows[0].object,null);
 await db.exec('alter default privileges revoke execute on functions from unexpected_fixture_role;');
 await db.exec(candidate);
 assert.deepEqual(await legacySnapshot(),originalLegacy);
 const login=async(s=sid)=>db.exec(`set test.uid='${actor}';set test.jwt='${JSON.stringify({sub:actor,role:'authenticated',session_id:s})}';`);
 await login();let count=0;
 const invoke=async(company,command,payload={},op=null,session=sid)=>{
  count++;
  const v=(await db.query(`select public.company_link_bound_v1('${company}','${session}',${op?`'${op}'`:'null'},'${command}','${JSON.stringify(payload)}'::jsonb) value`)).rows[0].value;
  assert.equal(v.company_id,company);assert.equal(v.actor_id,actor);assert.equal(v.session_id,session);return v.value;
 };
 for(const role of ['anon','service_role']){
  await db.exec(`set role ${role};`);
  await assert.rejects(invoke(ids(1),'workspace'),/permission denied/);await db.exec('reset role;');
 }
 await db.exec('set role authenticated;');await invoke(ids(1),'workspace');
 await assert.rejects(db.exec('select * from private.company_link_bound_operations'),/permission denied/);
 await assert.rejects(db.exec(`select private.require_company_link_bound_v1('${ids(1)}','${sid}')`),/permission denied/);
 await db.exec('reset role;');
 await invoke(ids(1),'set_enabled',{enabled:true},ids(201));
 await invoke(ids(2),'set_enabled',{enabled:true},ids(202));
 await invoke(ids(3),'set_enabled',{enabled:true},ids(203));
 assert.equal((await invoke(ids(2),'workspace')).enabled,true);
 const payload={target_company_id:ids(3),local_role:'customer',start_month:'2026-10-01'};
 const first=await invoke(ids(2),'request',payload,ids(204));
 assert.equal((await db.query(`select sender_company_id from private.trade_company_link_requests where id='${first.request_id}'`)).rows[0].sender_company_id,ids(2));
 assert.deepEqual(await invoke(ids(2),'request',payload,ids(204)),first);
 await assert.rejects(invoke(ids(2),'request',{...payload,start_month:'2026-11-01'},ids(204)),/another command/);
 await invoke(ids(3),'respond',{request_id:first.request_id,action:'accept'},ids(205));
 assert.equal((await db.query('select count(*)::integer n from public.trade_companies')).rows[0].n,2);
 assert.equal((await db.query(`select count(*)::integer n from public.trade_companies where company_id='${ids(1)}'`)).rows[0].n,0);
 await invoke(ids(2),'set_enabled',{enabled:false},ids(206));
 assert.equal((await invoke(ids(2),'result',{},ids(204))).state,'committed');
 for(const mutation of [
  'update private.company_link_bound_operations set command=command',
  'delete from private.company_link_bound_operations',
  'truncate private.company_link_bound_operations',
 ])await assert.rejects(db.exec(mutation),/append-only/);
 await assert.rejects(invoke(ids(2),'request',payload,ids(204)),/disabled/);
 await invoke(ids(2),'set_enabled',{enabled:true},ids(207));
 const second=await invoke(ids(2),'request',payload,ids(208));
 await db.exec(`create function private.fixture_link_failure() returns trigger language plpgsql as $$begin
  if current_setting('test.fail_attach',true)='1' and new.company_id='${ids(3)}' then raise exception 'synthetic second attachment failure'; end if;
  if current_setting('test.fail_notice',true)='1' and tg_table_name='app_notifications' then raise exception 'synthetic notification failure'; end if;
  return new;end$$;
 create trigger fixture_attach_failure before insert or update on public.trade_companies for each row execute function private.fixture_link_failure();
 create trigger fixture_notice_failure before insert on public.app_notifications for each row execute function private.fixture_link_failure();`);
 const snapshot=async()=>({companies:(await db.query('select * from public.trade_companies order by id')).rows,
  requests:(await db.query('select * from private.trade_company_link_requests order by id')).rows,
  notices:(await db.query('select * from public.app_notifications order by company_id,recipient_user_id,action_id')).rows,
  receipts:(await db.query('select * from private.company_link_bound_operations order by operation_id')).rows});
 let before=await snapshot();await db.exec("set test.fail_attach='1';");
 await assert.rejects(invoke(ids(3),'respond',{request_id:second.request_id,action:'accept'},ids(209)),/second attachment failure/);
 assert.deepEqual(await snapshot(),before);await db.exec("set test.fail_attach='0';set test.fail_notice='1';");
 before=await snapshot();await assert.rejects(invoke(ids(2),'request',{...payload,target_company_id:ids(1)},ids(210)),/notification failure/);
 assert.deepEqual(await snapshot(),before);await db.exec("set test.fail_notice='0';");
 if(native){
  const http=require('node:http');let accepted=0;
  const lostAckServer=http.createServer(async(req,res)=>{
   try{
    if(req.url==='/commit'){
     accepted++;await invoke(ids(1),'set_enabled',{enabled:false},ids(211));
     req.socket.destroy();return;
    }
    res.setHeader('content-type','application/json');
    res.end(JSON.stringify(await invoke(ids(1),'result',{},ids(211))));
   }catch(error){res.statusCode=500;res.end('synthetic fixture failure');}
  });
  await new Promise(resolve=>lostAckServer.listen(0,'127.0.0.1',resolve));
  try{
   const url=`http://127.0.0.1:${lostAckServer.address().port}`;
   await assert.rejects(fetch(url+'/commit',{method:'POST'}));
   const receipt=await(await fetch(url+'/result')).json();
   assert.equal(receipt.state,'committed');assert.equal(receipt.result.enabled,false);assert.equal(accepted,1);
   assert.equal((await db.query(`select enabled from private.trade_company_link_settings where company_id='${ids(1)}'`)).rows[0].enabled,false);
   console.log('NATIVE_COMPANY_LINK_COMMIT_ACK_LOSS_LOOKUP: 1');
  }finally{await new Promise(resolve=>lostAckServer.close(resolve));}
  const {Client}=require('pg'),other=new Client();await other.connect();
  try{
   const pid=(await other.query('select pg_backend_pid() pid')).rows[0].pid;
   await db.exec('begin');await invoke(ids(2),'workspace');
   const waiting=other.query(`update public.company_members set role='viewer' where company_id='${ids(2)}' and user_id='${actor}'`);
   let observed=false;
   for(let i=0;i<100&&!observed;i++)observed=(await db.query(`select wait_event_type='Lock' waiting from pg_stat_activity where pid=${pid}`)).rows[0]?.waiting===true;
   assert(observed,'actual role revoke must wait behind captured membership SHARE lock');
   await db.exec('commit');await waiting;
   await assert.rejects(invoke(ids(2),'workspace'),/role unavailable/);
   await db.exec(`update public.company_members set role='admin' where company_id='${ids(2)}' and user_id='${actor}'`);
   console.log('NATIVE_COMPANY_LINK_REVOKE_WAIT: 1');
   await db.exec(`update private.trade_company_link_settings set enabled=true where company_id='${ids(1)}';`);
   await other.query(`begin;select pg_advisory_xact_lock(hashtextextended('${ids(1)}',0));`);
   const mainPid=(await db.query('select pg_backend_pid() pid')).rows[0].pid;
   const requestWait=invoke(ids(2),'request',{...payload,target_company_id:ids(1)},ids(212));
   const expectedRejection=assert.rejects(requestWait,/disabled/);
   observed=false;
   for(let i=0;i<100&&!observed;i++){
    await other.query('select pg_stat_clear_snapshot()');
    observed=(await other.query(`select wait_event_type='Lock' waiting from pg_stat_activity where pid=${mainPid}`)).rows[0]?.waiting===true;
   }
   assert(observed,'actual request must wait behind company pair gate');
   await other.query(`update private.trade_company_link_settings set enabled=false where company_id='${ids(1)}';commit;`);
   await expectedRejection;
   assert.equal((await invoke(ids(2),'result',{},ids(212))).state,'unobserved');
   console.log('NATIVE_COMPANY_LINK_SETTINGS_OFF_WAIT: 1');
  }finally{await other.end();}
 }
 await login(sid2);
 assert.equal((await invoke(ids(2),'result',{},ids(204),sid2)).original_session_id,sid);
 await assert.rejects(invoke(ids(2),'request',payload,ids(204),sid2),/original session/);
 await assert.rejects(invoke(ids(2),'workspace',{},null,sid),/context unavailable/);
 await db.exec(`update public.company_members set role='viewer' where user_id='${actor}' and company_id='${ids(2)}';`);
 await assert.rejects(invoke(ids(2),'result',{},ids(204),sid2),/role unavailable/);
 await login();await db.exec(`update auth.sessions set not_after=clock_timestamp()-interval '1 minute' where id='${sid}';`);
 await assert.rejects(invoke(ids(1),'workspace'),/session unavailable/);
 console.log(JSON.stringify({engine:native?'Native PostgreSQL synthetic fixture':'PGlite synthetic fixture',calls:count,result:'PASS',realAuth:false,production:false}));
 if(native)await nativeClient.end();else await db.close();
})().catch(async e=>{console.error(e);if(nativeClient)await nativeClient.end();process.exitCode=1;});
