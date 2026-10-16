// Fresh disposable localhost PostgreSQL 17 only. No production connections.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const connectionString=process.env.SKO_INVOICE_MONTH_END_RACE_DATABASE_URL;
const database='sko_invoice_month_end_race_fixture';
const url=new URL(connectionString??'postgres://invalid');
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||
 !['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/'+database)
 throw Error('Only the disposable localhost invoice month-end database is permitted');
const pg=await import(pathToFileURL(process.argv[2]).href);
const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){
 const c=new Client({connectionString,application_name:name});
 if(!['127.0.0.1','localhost','::1'].includes(c.connectionParameters.host)||
 c.connectionParameters.database!==database)throw Error('Effective fixture connection changed');
 await c.connect();clients.push(c);
 await c.query("set statement_timeout='20s';set lock_timeout='10s'");
 return c;
}
const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
const uid=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const company='10000000-0000-0000-0000-000000000001';
const otherCompany='10000000-0000-0000-0000-000000000002';
const inv=n=>'20000000-0000-0000-0000-'+String(n).padStart(12,'0');
let admin,cron,app,approver,config,observer;
const settle=p=>{p.catch(()=>{});return p;};
async function blocked(name){
 const until=Date.now()+8000;
 while(Date.now()<until){
  await observer.query('select pg_stat_clear_snapshot()');
  const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=$1 and wait_event_type='Lock'",[name]);
  if(r.rows[0].n===1)return;
  await new Promise(resolve=>setTimeout(resolve,25));
 }
 throw Error('Actual lock wait was not observed: '+name);
}
const actor=async(c,u)=>{await c.query("select set_config('request.jwt.claim.sub',$1,false)",[u]);await c.query('set role authenticated');};
const dispatch=c=>c.query('select private.run_invoice_month_end_notifications() n');
const publicDispatch=c=>c.query('select public.enqueue_due_invoice_approval_notifications() n');
const approve=(c,i)=>c.query('select public.approve_invoice($1) approved',[i]);
const receiptCount=async i=>(await admin.query('select count(*)::int n from private.invoice_month_end_receipts where invoice_id=$1',[i])).rows[0].n;
const noticeCount=async i=>(await admin.query("select count(*)::int n from app_notifications where action_key='invoice_approval' and action_id=$1",[i])).rows[0].n;
async function addInvoice(n,{companyId=company,future=false}={}){
 await admin.query("insert into invoices(id,company_id,billing_period_end,status)values($1,$2,(date_trunc('month',current_date)+case when $3 then interval '1 month' else interval '-1 month' end)::date+14,'draft')",[inv(n),companyId,future]);
}
async function holdCompany(c){
 await c.query('begin');
 await c.query('select id from companies where id=$1 for update',[company]);
}
try{
 [admin,cron,app,approver,config,observer]=await Promise.all([
  connect('invoice-month-admin'),connect('invoice-month-cron'),connect('invoice-month-app'),
  connect('invoice-month-approver'),connect('invoice-month-config'),connect('invoice-month-observer')]);
 assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0,'Never clear an existing database');
 // Reuse the exact dependency bodies/fixture used by the isolated staged test.
 const isolated=await read('tool/test_invoice_month_end_notifications.mjs');
 const match=isolated.match(/await db\.exec\(("(?:\\.|[^"\\])*")\);/);
 assert.ok(match,'isolated fixture must remain a literal JSON string');
 await admin.query(JSON.parse(match[1]));
 await admin.query(await read('supabase/migrations/20261005081500_invoice_approval_workflow.sql'));
 await admin.query(await read('supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql'));
 await admin.query(await read('tool/staged/invoice_month_end_approval_notifications.sql'));
 await actor(app,uid(1));await actor(approver,uid(1));await actor(config,uid(1));
 await admin.query('insert into private.invoice_month_end_rollout values($1,true)',[company]);
 await addInvoice(1);
 // Cron and app both wait behind the same actual company row lock.
 await holdCompany(admin);
 const cronFirst=settle(dispatch(cron));await blocked('invoice-month-cron');
 const appSecond=settle(publicDispatch(app));await blocked('invoice-month-app');
 await admin.query('commit');
 const sends=await Promise.all([cronFirst,appSecond]);
 assert.equal(sends.reduce((n,r)=>n+r.rows[0].n,0),1);
 assert.equal(await receiptCount(inv(1)),1);assert.equal(await noticeCount(inv(1)),1);
 // Notification commits before queued approval; approval sees the new receipt.
 await addInvoice(2);await holdCompany(admin);
 const notification=settle(dispatch(cron));await blocked('invoice-month-cron');
 const approval=settle(approve(approver,inv(2)));await blocked('invoice-month-approver');
 await admin.query('commit');await notification;
 assert.equal((await approval).rows[0].approved,true);
 assert.equal(await receiptCount(inv(2)),1);
 // Reverse order: approval without a committed receipt must fail, not wait forever.
 await addInvoice(3);await holdCompany(admin);
 const premature=settle(approve(approver,inv(3)));await blocked('invoice-month-approver');
 const laterNotice=settle(dispatch(cron));await blocked('invoice-month-cron');
 await admin.query('commit');
 await assert.rejects(premature,e=>e.code==='42501');
 await laterNotice;assert.equal(await receiptCount(inv(3)),1);
 // Cancellation holds company -> invoice; cron follows, without a new notice.
 await approve(approver,inv(1));
 await approver.query('begin');await approver.query('select public.cancel_invoice_approval($1)',[inv(1)]);
 const afterCancel=settle(dispatch(cron));await blocked('invoice-month-cron');
 await approver.query('commit');
 assert.equal((await afterCancel).rows[0].n,0);
 assert.equal(await noticeCount(inv(1)),1);
 assert.equal((await admin.query("select count(*)::int n from invoice_approval_audit where invoice_id=$1 and action='cancelled'",[inv(1)])).rows[0].n,1);
 assert.equal((await admin.query("select count(*)::int n from invoice_approval_audit where invoice_id=$1 and action='approved'",[inv(1)])).rows[0].n,1);
 // Registered-approver reconfiguration holds the same lock order.
 await config.query('begin');await config.query('select public.set_invoice_approvers($1::uuid[])',[[uid(2)]]);
 const afterReconfigure=settle(dispatch(cron));await blocked('invoice-month-cron');
 await config.query('commit');await afterReconfigure;
 assert.equal((await admin.query('select private.invoice_month_end_eligible($1,$2) allowed',[inv(1),uid(1)])).rows[0].allowed,false);
 assert.equal((await admin.query('select private.invoice_month_end_eligible($1,$2) allowed',[inv(1),uid(2)])).rows[0].allowed,true);
 // Change back to the original person: a new registration version needs a receipt.
 await config.query('begin');await config.query('select public.set_invoice_approvers($1::uuid[])',[[uid(1)]]);
 const afterReregister=settle(publicDispatch(app));await blocked('invoice-month-app');
 await config.query('commit');await afterReregister;
 assert.equal((await admin.query('select count(*)::int n from private.invoice_month_end_receipts r join invoice_approvers a on a.company_id=$1 and a.user_id=r.recipient_user_id and a.created_at=r.approver_registered_at where r.invoice_id=$2',[company,inv(1)])).rows[0].n,1);
 assert.equal((await dispatch(cron)).rows[0].n,0);
 // A failure after the notification INSERT must roll back notification and receipt.
 const enqueue=(await admin.query("select pg_get_functiondef('private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure) def")).rows[0].def;
 const failing=enqueue.replace('return v_id;', "if current_setting('test.fail_notification',true)='on' then raise exception 'fixture notification failure' using errcode='55000'; end if; return v_id;");
 assert.notEqual(failing,enqueue);await admin.query(failing);
 await addInvoice(4);await cron.query("set test.fail_notification='on'");
 await assert.rejects(dispatch(cron),e=>e.code==='55000');
 assert.equal(await noticeCount(inv(4)),0);assert.equal(await receiptCount(inv(4)),0);
 await cron.query("set test.fail_notification='off'");
 const retry=await Promise.all([dispatch(cron),publicDispatch(app)]);
 assert.equal(retry.reduce((n,r)=>n+r.rows[0].n,0),1);
 assert.equal(await noticeCount(inv(4)),1);assert.equal(await receiptCount(inv(4)),1);
 // OFF-company behavior is unchanged by the cron path.
 await addInvoice(5,{companyId:otherCompany});
 const offNotices=await noticeCount(inv(5));
 await Promise.all([dispatch(cron),publicDispatch(app)]);
 assert.equal(await receiptCount(inv(5)),0);assert.equal(await noticeCount(inv(5)),offNotices);
 assert.equal((await admin.query('select private.invoice_month_end_eligible($1,$2) allowed',[inv(5),uid(4)])).rows[0].allowed,true);
 // Fifteenth-day closing dates still wait for the target month's last day.
 await addInvoice(6,{future:true});
 await Promise.all([dispatch(cron),publicDispatch(app)]);
 assert.equal(await receiptCount(inv(6)),0);assert.equal(await noticeCount(inv(6)),0);
 await assert.rejects(approve(approver,inv(6)),e=>e.code==='42501');
 assert.equal((await admin.query("select private.invoice_month_end_due('2026-10-15','2026-10-15T03:00:00Z') allowed")).rows[0].allowed,false);
 const duplicates=await admin.query('select invoice_id,recipient_user_id,approver_registered_at,period_end,count(*) from private.invoice_month_end_receipts group by 1,2,3,4 having count(*)>1');
 assert.equal(duplicates.rowCount,0);
 console.log('PASS PostgreSQL 17 real lock waits: cron/app, approval/notice, cancellation, registration revisions and failed-notice retry; no timeout/deadlock accepted');
}finally{
 await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));
}
