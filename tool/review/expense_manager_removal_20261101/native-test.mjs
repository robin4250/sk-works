import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from '../../fixtures/expense_cost_fixture.mjs';
import {fixtureTarget} from './fixture-target.mjs';

const config=fixtureTarget();
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
if(typeof Client!=='function')throw Error('Pinned pg Client unavailable');
const clients=[];let checks=0;
async function client(name=config.application_name){const c=new Client({...config,application_name:name});clients.push(c);await c.connect();
 const p=c.connectionParameters;assert.equal(p.host,config.host);assert.equal(p.database,config.database);assert.equal(Number(p.port),config.port);
 await c.query("set statement_timeout='15s';set lock_timeout='4s'");return c;}
function pass(name){checks++;console.log(`PASS ${name}`);}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try{
 const c=await client();const server=(await c.query('select current_database() db,inet_server_addr()::text ip,version() version')).rows[0];
 assert.equal(server.db,config.database);assert.equal(server.ip,process.env.SKO_EXPENSE_FIXTURE_SERVER_IP??'127.0.0.1');
 assert.match(server.version,/PostgreSQL 17\.6\b/);
 assert.equal((await c.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','storage')")).rows[0].n,0);
 const db={exec:sql=>c.query(sql),query:(sql,p)=>c.query(sql,p)};
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await c.query(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await c.query(`create table if not exists auth.users(id uuid primary key);
  alter table auth.users add column if not exists deleted_at timestamptz,
   add column if not exists is_anonymous boolean default false,add column if not exists banned_until timestamptz;
  create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
  create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object(
   'sub',current_setting('test.uid',true),'role',coalesce(nullif(current_setting('test.role',true),''),'authenticated'),
   'session_id',current_setting('test.sid',true),'exp',floor(extract(epoch from clock_timestamp()))+3600)$$;
  alter table private.expense_claims add column receipt_object_path text;
 `);
 await c.query(fs.readFileSync('supabase/migrations/20260919213000_add_app_notifications.sql','utf8'));
 const company=id(1),worker=id(2),manager=id(3),applicant=id(9),sid=id(10),applicantSid=id(11);
 await c.query(`insert into auth.users(id) values('${manager}'),('${applicant}'),('${id(8)}');
  insert into auth.sessions values('${sid}','${manager}',null),('${applicantSid}','${applicant}',null);
  insert into companies(id,tax_rate) values('${company}',10),('${id(7)}',10);
  insert into company_members values('${company}','${manager}','owner'),('${company}','${applicant}','viewer');
  insert into workers(id,company_id,name,user_id) values('${worker}','${company}','本人','${applicant}');
  insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${manager}']::uuid[],1);
  set test.uid='${manager}';set test.sid='${sid}';grant usage on schema private,auth to authenticated;
 `);
 const protectedFunctions=['private.expense_cost_claim_guard()','private.expense_cost_choice_guard()',
  'private.expense_cost_components(text,uuid,uuid,date,date,uuid)','private.expense_cost_finalize()',
  'private.expense_document_claims(text,uuid,uuid,date)','private.capture_expense_document()'];
 async function digest(){return (await c.query(`select jsonb_agg(jsonb_build_object('oid',p.oid,'attributes',to_jsonb(p),
  'definition',pg_get_functiondef(p.oid)) order by p.oid) value from pg_proc p where p.oid=any($1::regprocedure[])`,[protectedFunctions])).rows[0].value;}
 const beforeFunctions=await digest();
 const source=fs.readFileSync('docs/candidates/expense_manager_removal_20261101.sql.review-only','utf8');
 await c.query(source);assert.deepEqual(await digest(),beforeFunctions);pass('existing financial guards and shared document/payroll readers are unchanged');
 const api=await client('expense-removal-api-a'),api2=await client('expense-removal-api-b');
 await Promise.all([api,api2].map(conn=>conn.query(`set role authenticated;set test.uid='${manager}';set test.sid='${sid}'`)));
 async function identity(actor,session){await Promise.all([c,api,api2].map(conn=>conn.query(`set test.uid='${actor}';set test.sid='${session}'`)));}
 async function createClaim(n){await c.query(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen,receipt_object_path)
  values($1,$2,$3,'本人',$4,'2026-10-01','2026-10-01T00:00:00Z','領収書付き経費',1234,'retained/original.png')`,[id(n),company,worker,applicant]);}
 async function remove(cmd,n,revision=1,pSession=sid,reason='登録内容を訂正'){
  return (await api.query('select public.expense_manager_remove($1,$2,$3,$4,$5,$6) value',[id(cmd),company,id(n),revision,pSession,reason])).rows[0].value;}
 async function counts(){return (await c.query(`select
  (select count(*) from private.expense_manager_removals)::int removals,
  (select count(*) from public.app_notifications)::int notices`)).rows[0];}
 await createClaim(100);
 await assert.rejects(remove(200,100),/OFF/);assert.deepEqual(await counts(),{removals:0,notices:0});pass('default OFF prevents deletion and notification');
 await c.query('update private.expense_manager_removal_state set enabled=true');
 const first=await remove(200,100);assert.equal(first.manager_deleted,true);assert.equal(first.financial_state,'withdrawn_unfinalized');
 assert.equal(first.notification_state,'stored');assert.equal(first.correction_required,false);
 const row=(await c.query('select * from private.expense_claims where id=$1',[id(100)])).rows[0];
 assert.equal(row.withdrawn,true);assert.equal(row.revision,2);assert.equal(row.receipt_object_path,'retained/original.png');pass('unconsumed pending claim is logically withdrawn while receipt path and original history are retained');
 assert.deepEqual(await remove(200,100),first);assert.deepEqual(await counts(),{removals:1,notices:1});pass('same command replays one receipt and one applicant notification');
 await assert.rejects(remove(200,100,1,sid,'別の理由'),/Fixed expense removal differs/);pass('same command with changed payload is rejected');
 await identity(applicant,applicantSid);
 const personal=(await api.query('select public.expense_personal_history($1,$2,$3) value',[company,worker,'2026-10-01'])).rows[0].value;
 assert.equal(personal.find(x=>x.id===id(100)).manager_deleted,true);
 const notice=(await api.query('select public.expense_manager_removal_notice($1) value',[first.notification_id])).rows[0].value;
 assert.equal(notice.manager_deleted,true);assert.equal(notice.amount_yen,1234);assert.equal('receipt_object_path' in notice,false);
 assert.deepEqual(await counts(),{removals:1,notices:1});pass('applicant notification is read-only, scoped and excludes receipt paths');
 await assert.rejects(remove(201,100),/access unavailable|Selected expense manager/);pass('applicant cannot use manager deletion permissions');
 await identity(manager,sid);
 const workspace=(await c.query('select public.expense_review_flow_workspace($1,$2) value',[company,'2026-10-01'])).rows[0].value;
 assert.equal(workspace.claims.some(x=>x.id===id(100)),false);pass('legacy manager workspace cannot resurface tombstoned claims');
 await createClaim(101);await c.query("select public.expense_confirm_review($1,$2,1,'reject',null,null,null,'却下')",[id(211),id(101)]);
 assert.equal((await remove(212,101,2)).manager_deleted,true);pass('already rejected unconsumed claim can be removed');
 await createClaim(102);await c.query("select public.expense_confirm_review($1,$2,1,'approve','ownCompany',null,'cash','承認')",[id(213),id(102)]);
 assert.equal((await remove(214,102,2)).manager_deleted,true);pass('already approved unconsumed claim can be removed without changing an existing final document');
 await createClaim(103);await assert.rejects(remove(215,103,99),/changed; reload/);pass('revision drift is rejected');
 await identity(manager,id(999));await assert.rejects(remove(216,103),/access unavailable/);
 await identity(manager,sid);pass('unknown live SID is rejected');
 await c.query("update auth.users set is_anonymous=true where id=$1",[manager]);await assert.rejects(remove(216,103),/access unavailable/);
 await c.query("update auth.users set is_anonymous=false,banned_until=clock_timestamp()+interval '1 hour' where id=$1",[manager]);await assert.rejects(remove(216,103),/access unavailable/);
 await c.query('update auth.users set banned_until=null where id=$1',[manager]);pass('anonymous and banned Auth users cannot delete');
 const snapshotBefore=(await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[id(103)])).rows[0].value;
 await c.query("create function private.fixture_notice_failure() returns trigger language plpgsql as $$begin raise exception 'fixture notification failure';end$$;create trigger fixture_notice_failure before insert on app_notifications for each row execute function private.fixture_notice_failure()");
 await assert.rejects(remove(217,103),/fixture notification failure/);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[id(103)])).rows[0].value,snapshotBefore);
 await c.query('drop trigger fixture_notice_failure on app_notifications');pass('notification failure rolls back claim update and deletion receipt together');
 await createClaim(104);await c.query("select public.expense_confirm_review($1,$2,1,'approve','ownCompany',null,'paid','保持')",[id(218),id(104)]);
 await c.query(`insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
  values($1,'cost_recovery',$2,'invoice',$3,1,2,1234,jsonb_build_object('original',true))`,[id(104),company,id(300)]);
 const consumedBefore=(await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[id(104)])).rows[0].value;
 const ledgerBefore=(await c.query('select to_jsonb(e) value from private.expense_amount_consumptions e where claim_id=$1',[id(104)])).rows[0].value;
 const frozen=await remove(219,104,2);assert.equal(frozen.financial_state,'finalized_original_retained');assert.equal(frozen.correction_required,true);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[id(104)])).rows[0].value,consumedBefore);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_amount_consumptions e where claim_id=$1',[id(104)])).rows[0].value,ledgerBefore);pass('consumed claim and immutable financial ledger stay byte-equivalent; correction remains explicitly required');
 await assert.rejects(c.query("insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot) values($1,'reimbursement',$2,'payroll',$3,1,2,1234,'{}')",[id(104),company,id(301)]),/cannot be reused/);pass('a tombstone blocks reuse under another financial purpose');
 await assert.rejects(c.query('update private.expense_claims set revision=revision+1 where id=$1',[id(104)]),/cannot be reused|帳票確定済み/);
 await assert.rejects(c.query("update private.expense_settlement_choices set method='payroll' where claim_id=$1",[id(104)]),/cannot be reused|帳票確定済み/);pass('legacy review/settlement update cannot revive a manager-deleted claim');
 await createClaim(105);const countsBeforeRace=await counts();
 await c.query('begin');await c.query('select id from private.expense_claims where id=$1 for update',[id(105)]);
 const parameters=[id(221),company,id(105),1,sid,'同じ削除の再確認'];
 const raceA=api.query('select public.expense_manager_remove($1,$2,$3,$4,$5,$6) value',parameters);
 const raceB=api2.query('select public.expense_manager_remove($1,$2,$3,$4,$5,$6) value',parameters);
 raceA.catch(()=>{});raceB.catch(()=>{});
 let waiting=false;
 for(let attempt=0;attempt<150;attempt++){
  const n=(await c.query("select count(*)::int n from pg_stat_activity where application_name in ('expense-removal-api-a','expense-removal-api-b') and wait_event_type='Lock'")).rows[0].n;
  if(n===2){waiting=true;break;}await new Promise(resolve=>setTimeout(resolve,20));
 }
 assert.equal(waiting,true,'two real API connections must wait on the captured claim');
 await c.query('commit');const receipts=await Promise.all([raceA,raceB]);
 assert.deepEqual(receipts[0].rows[0].value,receipts[1].rows[0].value);
 const countsAfterRace=await counts();assert.equal(countsAfterRace.removals,countsBeforeRace.removals+1);assert.equal(countsAfterRace.notices,countsBeforeRace.notices+1);
 pass('two actual waiting API connections produce one removal and one notification');
 await c.query('update private.expense_manager_removal_state set enabled=false');
 assert.deepEqual((await api.query('select public.expense_manager_removal_result($1,$2) value',[id(200),company])).rows[0].value,first);
 assert.deepEqual(await remove(200,100),first);await assert.rejects(remove(220,103),/OFF/);pass('OFF stops new work but permits authorized result-only reconciliation');
 await assert.rejects(c.query('update private.expense_manager_removals set result=result'),/immutable/);pass('deletion audit cannot be edited');
 for(const role of ['anon','service_role'])assert.equal((await c.query('select has_function_privilege($1,$2,\'EXECUTE\') value',[role,'public.expense_manager_remove(uuid,uuid,uuid,integer,uuid,text)'])).rows[0].value,false);
 assert.deepEqual(await digest(),beforeFunctions);pass('financial function definitions, owner/ACL and final snapshot readers remain unchanged');
 // Deliberate RED: the unchanged shared reader can still show a consumed row.
 const oldReader=(await c.query("select private.expense_document_claims('payroll',$1,$2,'2026-10-01') value",[company,worker])).rows[0].value;
 assert.equal(oldReader.some(x=>x.id===id(104)),true);pass('unresolved shared-reader legacy exposure is observed, not hidden or called production-complete');
 console.log(JSON.stringify({contract:'expense_manager_removal_fixture_v1',checks,deployable:false,
  auth:'synthetic JWT/session rows; not real GoTrue',shared_payroll_reader_connected:false,production_changed:false}));
}finally{await Promise.allSettled(clients.map(c=>c.end()));}
