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
 await db.exec(candidate);
 const login=async(s=sid)=>db.exec(`set test.uid='${actor}';set test.jwt='${JSON.stringify({sub:actor,role:'authenticated',session_id:s})}';`);
 await login();let count=0;
 const invoke=async(company,command,payload={},op=null,session=sid)=>{
  count++;
  const v=(await db.query(`select public.company_link_bound_v1('${company}','${session}',${op?`'${op}'`:'null'},'${command}','${JSON.stringify(payload)}'::jsonb) value`)).rows[0].value;
  assert.equal(v.company_id,company);assert.equal(v.actor_id,actor);assert.equal(v.session_id,session);return v.value;
 };
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
 await assert.rejects(invoke(ids(2),'request',payload,ids(204)),/disabled/);
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
