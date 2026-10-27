import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(process.env.SKO_ADJUSTMENT_ROOT);
let wrapper=await readFile(resolve(process.env.SKO_PREVIEW_WRAPPER),'utf8');
const checkSql=await readFile(process.env.SKO_MONTH_CLOSE_SQL,'utf8');
const guardedSql=await readFile(process.env.SKO_GUARDED_SQL,'utf8');
const approvalSql=await readFile(process.env.SKO_APPROVAL_SQL,'utf8');
const approverCore=await readFile(process.env.SKO_APPROVER_CORE,'utf8');
const noticeSql=await readFile(process.env.SKO_NOTICE_SQL,'utf8');
const noticeReadiness=await readFile(process.env.SKO_NOTIFICATION_READINESS_SQL,'utf8');
const deliverySql=await readFile(process.env.SKO_DELIVERY_SQL,'utf8');
const entrySql=await readFile(process.env.SKO_APPROVAL_ENTRY_SQL,'utf8');
const approvalGuard=await readFile(process.env.SKO_APPROVAL_GUARD_SQL,'utf8');
const legacyNoticeGuard=await readFile(process.env.SKO_LEGACY_GUARD_SQL,'utf8');
const triggerFile=await readFile(process.env.SKO_NOTIFY_TRIGGER,'utf8');
const triggerStart=triggerFile.indexOf('CREATE OR REPLACE FUNCTION private.enqueue_notification(');assert.ok(triggerStart>=0);
const triggerEnd=triggerFile.indexOf('$function$;',triggerStart);assert.ok(triggerEnd>triggerStart);
const enqueueBody=triggerFile.slice(triggerStart,triggerEnd+'$function$;'.length);
const ensureApprovals=await readFile(resolve(root,'supabase/tests/fixtures/trade_document_adjustments_20261026/private.ensure_invoice_approval_rows.sql'),'utf8');
const declarations=`const closeSql=${JSON.stringify(checkSql)};const guardedSql=${JSON.stringify(guardedSql)};const approvalSql=${JSON.stringify(approvalSql)};const approverCore=${JSON.stringify(approverCore)};const noticeSql=${JSON.stringify(noticeSql)};const noticeReadiness=${JSON.stringify(noticeReadiness)};const deliverySql=${JSON.stringify(deliverySql)};const entrySql=${JSON.stringify(entrySql)};const approvalGuard=${JSON.stringify(approvalGuard)};const legacyNoticeGuard=${JSON.stringify(legacyNoticeGuard)};const enqueueBody=${JSON.stringify(enqueueBody)};const ensureApprovals=${JSON.stringify(ensureApprovals)};\n`;
const injection=`
// Synthetic past month: reuse existing real refresh/preview and frozen snapshot.
await db.exec("alter table public.attendance_entries add column if not exists source_report_id uuid;alter table public.attendance_verifications add column if not exists id uuid;alter table public.attendance_verifications add column if not exists worker_id uuid;alter table public.attendance_verifications add column if not exists site_id uuid;alter table public.attendance_verifications add column if not exists work_date date;alter table public.attendance_verifications add column if not exists confirmed_at timestamptz;alter table public.attendance_verifications add column if not exists daily_report_id uuid;alter table public.attendance_verifications add column if not exists route_assignment_id uuid;alter table public.daily_reports add column if not exists site_id uuid;alter table public.daily_reports add column if not exists report_date date;alter table public.daily_reports add column if not exists status text;alter table public.daily_reports add column if not exists signed_at timestamptz;alter table public.daily_reports add column if not exists representative_signature_json jsonb;alter table public.daily_reports add column if not exists supervisor_signature_json jsonb;alter table public.daily_reports add column if not exists route_assignment_id uuid;alter table public.daily_report_workers add column if not exists worker_id uuid;");
await db.exec("create table private.fixture_route_source(report_id uuid,worker_id uuid,customer_id uuid,source_clock_in_id uuid,source_ready boolean);create function private.route_signed_checkout_sources(uuid,date,date) returns table(report_id uuid,worker_id uuid,customer_id uuid,source_clock_in_id uuid,source_ready boolean) language sql as $$select * from private.fixture_route_source$$;");
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2020-10-25','2020-10-27')",[company,site]);
const days=['2020-10-16','2020-10-22','2020-10-24','2020-10-26'];
for(let j=0;j<days.length;j++){
 const report=id(900+j),start=id(910+j),end=id(920+j);
 await db.query("insert into daily_reports(id,company_id,site_id,report_date,status,signed_at,representative_signature_json,supervisor_signature_json) values($1,$2,$3,$4,'signed',now(),'[1]','[1]')",[report,company,site,days[j]]);
 await db.query('insert into daily_report_workers(report_id,worker_id) values($1,$2)',[report,worker]);
 await db.query('update attendance_entries set source_report_id=$1 where company_id=$2 and site_id=$3 and work_date=$4',[report,company,site,days[j]]);
 await db.query("insert into attendance_verifications(id,company_id,worker_id,site_id,work_date,event_type,confirmed_at,daily_report_id) values($1,$2,$3,$4,$5,'clock_in',now(),$6)",[start,company,worker,site,days[j],report]);
 await db.query("insert into attendance_verifications(id,company_id,worker_id,site_id,work_date,event_type,confirmed_at,daily_report_id,source_clock_in_id) values($1,$2,$3,$4,$5,'clock_out',now(),$6,$7)",[end,company,worker,site,days[j],report,start]);
}
const rr=id(940),rs=id(941),ro=id(942),route=id(943);
await db.query("insert into daily_reports(id,company_id,report_date,status,signed_at,representative_signature_json,supervisor_signature_json,route_assignment_id) values($1,$2,'2020-10-12','signed',now(),'[1]','[1]',$3)",[rr,company,route]);
await db.query('insert into daily_report_workers(report_id,worker_id) values($1,$2)',[rr,worker]);
await db.query("insert into attendance_verifications(id,company_id,worker_id,work_date,event_type,confirmed_at,daily_report_id,route_assignment_id) values($1,$2,$3,'2020-10-12','clock_in',now(),$4,$5)",[rs,company,worker,rr,route]);
await db.query("insert into attendance_verifications(id,company_id,worker_id,work_date,event_type,confirmed_at,daily_report_id,route_assignment_id,source_clock_in_id) values($1,$2,$3,'2020-10-12','clock_out',now(),$4,$5,$6)",[ro,company,worker,rr,route,rs]);
await db.query('insert into private.fixture_route_source values($1,$2,$3,$4,true)',[rr,worker,customer,rs]);
await db.exec(\${JSON.stringify(closeSql)});await db.exec(\${JSON.stringify(guardedSql)});
// Real approval mutation contract, isolated and rolled back after verification.
await db.exec("create table public.invoice_approvers(company_id uuid,user_id uuid,position integer);alter table public.invoice_approvals add column company_id uuid;alter table public.invoice_approvals add column approver_user_id uuid;alter table public.invoice_approvals add column position integer;alter table public.invoice_approvals add column approved_at timestamptz;create unique index fixture_invoice_approval_unique on public.invoice_approvals(invoice_id,approver_user_id);alter table public.invoice_approval_audit add column actor_user_id uuid;alter table public.invoice_approval_audit add column action text;");
await db.exec(\${JSON.stringify(ensureApprovals)});await db.exec(\${JSON.stringify(approvalSql)});await db.exec(\${JSON.stringify(approverCore)});
await db.query('insert into public.invoice_approvers values($1,$2,1)',[company,actor]);await db.query('select private.ensure_invoice_approval_rows($1)',[frozen.id]);
await db.query("insert into public.company_members(company_id,user_id,role) values($1,$2,'worker')",[company,id(969)]);
await db.query("select set_config('test.uid',$1,false)",[id(969)]);await assert.rejects(db.query('select invoice_month_close_candidate.approve($1)',[frozen.id]),/invoice approver permission required/);
await db.query("select set_config('test.uid',$1,false)",[actor]);
const readiness=async()=>(await db.query('select invoice_month_close_candidate.guarded($1) v',[frozen.id])).rows[0].v;
assert.equal(await readiness(),'ready');
const savedCore=(await db.query("select pg_get_functiondef('invoice_month_close_candidate.preview_for_approver(uuid)'::regprocedure) v")).rows[0].v;
const changedCore=savedCore.replace('declare'+String.fromCharCode(10),'declare'+String.fromCharCode(10)+' -- synthetic drift'+String.fromCharCode(10));assert.notEqual(changedCore,savedCore);
await db.exec(changedCore);assert.equal(await readiness(),'source_proof_missing');await db.exec(savedCore);assert.equal(await readiness(),'ready');
await db.exec(\${JSON.stringify(noticeSql)});await db.exec(\${JSON.stringify(noticeReadiness)});
await db.exec('update invoice_month_close_candidate.notice_settings set enabled=true');
// Trusted private background path has no auth.uid; it checks the explicit
// recipient against pending approval and does not impersonate any account.
await db.query("select set_config('test.uid','',false)");
const notice=() => db.query('select invoice_month_close_candidate.prepare_notice($1,$2) v',[frozen.id,actor]);
await assert.rejects(db.query('select invoice_month_close_candidate.prepare_notice($1,$2)',[frozen.id,id(969)]),/notice_unavailable/);
const noticeId=(await notice()).rows[0].v;assert.equal((await notice()).rows[0].v,noticeId);
assert.equal((await db.query('select invoice_month_close_candidate.notice_current($1) v',[noticeId])).rows[0].v,true);
await db.exec("create table public.app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);");
await db.exec(\${JSON.stringify(enqueueBody)});await db.exec(\${JSON.stringify(deliverySql)});await db.exec(\${JSON.stringify(approvalGuard)});await db.exec(\${JSON.stringify(entrySql)});
await db.exec('create trigger fixture_invoice_approval_guard before insert or update on public.invoices for each row execute function invoice_month_close_candidate.guard_invoice_transition();create trigger fixture_approval_transition_guard before insert or update on public.invoice_approvals for each row execute function invoice_month_close_candidate.guard_approval_transition()');
await db.exec(\${JSON.stringify(legacyNoticeGuard)});await db.exec('create trigger fixture_legacy_invoice_notice after insert or update on public.invoices for each row execute function private.invoice_approval_rows_trigger()');
assert.equal((await db.query("select md5(prosrc) h from pg_proc where oid='private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure")).rows[0].h,'260ef8dc60ec1917cc0c8dc85ea52872');
const deliver=()=>db.query('select invoice_month_close_candidate.deliver_notice($1) v',[noticeId]);
await assert.rejects(deliver(),/delivery_disabled/);await db.exec('update invoice_month_close_candidate.delivery_settings set enabled=true');await assert.rejects(deliver(),/delivery_disabled/);await db.exec('update invoice_month_close_candidate.approval_guard_settings set enabled=true');
await db.exec("create function invoice_month_close_candidate.fixture_delivery_abort() returns trigger language plpgsql as $$begin raise exception 'fixture_delivery_abort';end$$;create trigger fixture_delivery_abort before insert on invoice_month_close_candidate.delivery_receipts for each row execute function invoice_month_close_candidate.fixture_delivery_abort()");
await assert.rejects(deliver(),/fixture_delivery_abort/);assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,0);
await db.exec('drop trigger fixture_delivery_abort on invoice_month_close_candidate.delivery_receipts');
let notificationId=(await deliver()).rows[0].v;assert.equal((await deliver()).rows[0].v,notificationId);
assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,1);
if(process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL){
 // Start a new synthetic delivery race after cleaning the prior fixture-only result.
 await db.query('delete from invoice_month_close_candidate.delivery_receipts where notice_id=$1',[noticeId]);await db.query('delete from public.app_notifications where id=$1',[notificationId]);
 const {connectFixture}=await import(process.argv[2]);const d1=await connectFixture(),d2=await connectFixture();
 try{
  const delivered=await Promise.all([d1.query('select invoice_month_close_candidate.deliver_notice($1) v',[noticeId]),d2.query('select invoice_month_close_candidate.deliver_notice($1) v',[noticeId])]);
  notificationId=delivered[0].rows[0].v;assert.equal(delivered[1].rows[0].v,notificationId);
  assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int n from invoice_month_close_candidate.delivery_receipts')).rows[0].n,1);
  console.log(JSON.stringify({fixture_concurrent_delivery_exactly_once:true}));
 }finally{await d1.end();await d2.end();}
}
await db.query("select set_config('test.uid',$1,false)",[id(969)]);await assert.rejects(db.query('select invoice_month_close_candidate.ticket_from_notification($1)',[notificationId]),/notice_unavailable/);
await db.query("select set_config('test.uid',$1,false)",[actor]);await db.exec('update invoice_month_close_candidate.approval_guard_settings set enabled=false');await assert.rejects(db.query('select invoice_month_close_candidate.ticket_from_notification($1)',[notificationId]),/notice_unavailable/);await assert.rejects(deliver(),/delivery_disabled/);await db.exec('update invoice_month_close_candidate.approval_guard_settings set enabled=true');const ticket=(await db.query('select invoice_month_close_candidate.ticket_from_notification($1) v',[notificationId])).rows[0].v.ticket_id;
assert.equal((await db.query('select invoice_month_close_candidate.consume_notice_ticket($1) v',[ticket])).rows[0].v,frozen.id);
const approvalTicket=(await db.query('select invoice_month_close_candidate.ticket_from_notification($1) v',[notificationId])).rows[0].v.ticket_id;
await db.exec('update invoice_month_close_candidate.approval_guard_settings set enabled=true');
assert.equal((await db.query('select public.enqueue_due_invoice_approval_notifications() n')).rows[0].n,0);
await assert.rejects(db.query('update public.invoices set approval_finalized_at=now() where id=$1',[frozen.id]),/notification_approval_required/);
await assert.rejects(db.query("update public.invoice_approvals set status='approved' where invoice_id=$1",[frozen.id]),/notification_approval_required/);
assert.equal((await db.query('select count(*)::int n from invoice_month_close_candidate.approval_permits')).rows[0].n,0);
console.log(JSON.stringify({fixture_direct_invoice_and_approval_bypass_rejected:true}));
await db.query("select set_config('test.uid','',false)");
await addExtras();assert.equal((await db.query('select invoice_month_close_candidate.notice_current($1) v',[noticeId])).rows[0].v,false);await assert.rejects(notice(),/notice_not_ready/);await assert.rejects(deliver(),/notice_not_ready/);
await db.query("select set_config('test.uid',$1,false)",[actor]);await assert.rejects(db.query('select invoice_month_close_candidate.approve_from_notice($1)',[approvalTicket]),/notice_unavailable/);
await db.query("select set_config('test.uid','',false)");
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2020-10-25','2020-10-27')",[company,site]);
await db.query("update daily_reports set status='draft' where id=$1",[id(900)]);assert.equal((await db.query('select invoice_month_close_candidate.notice_current($1) v',[noticeId])).rows[0].v,false);await db.query("update daily_reports set status='signed' where id=$1",[id(900)]);
await db.query("select set_config('test.uid',$1,false)",[actor]);
await db.query('begin');assert.equal((await db.query('select invoice_month_close_candidate.approve_from_notice($1) v',[approvalTicket])).rows[0].v,true);assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,1);await db.query('rollback');
assert.equal((await db.query('select consumed_at is null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[approvalTicket])).rows[0].v,true);
assert.equal((await db.query('select count(*)::int n from invoice_month_close_candidate.approval_permits')).rows[0].n,0);await db.exec('update invoice_month_close_candidate.approval_guard_settings set enabled=false');
for(const role of ['anon','authenticated','service_role']){assert.equal((await db.query("select has_function_privilege($1,'invoice_month_close_candidate.approve_from_notice(uuid)','EXECUTE') v",[role])).rows[0].v,false);assert.equal((await db.query("select has_function_privilege($1,'invoice_month_close_candidate.notification_readiness(uuid,uuid)','EXECUTE') v",[role])).rows[0].v,false);}
console.log(JSON.stringify({fixture_private_real_notice_readiness:true,no_recipient_impersonation:true,wrong_recipient_denied:true,stale_notice_denied:true,fixture_internal_delivery_once:true,fixture_delivery_rollback:true,fixture_notification_approval_atomic:true,fixture_legacy_notification_suppressed:true,no_real_notification:true,route_source_stub:true}));
await db.query('begin');assert.equal((await db.query('select invoice_month_close_candidate.approve($1) v',[frozen.id])).rows[0].v,true);
assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='approved'",[frozen.id])).rows[0].n,1);
assert.equal((await db.query("select count(*)::int n from public.invoice_approval_audit where invoice_id=$1 and action='approved'",[frozen.id])).rows[0].n,1);await db.query('rollback');
assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='pending'",[frozen.id])).rows[0].n,1);
// A regular company member configured as second approver must work without
// invoice-management permissions and must not gain direct core execution.
await db.query('begin');await db.query('insert into public.invoice_approvers values($1,$2,2)',[company,id(969)]);await db.query('select private.ensure_invoice_approval_rows($1)',[frozen.id]);
assert.equal((await db.query('select invoice_month_close_candidate.approve($1) v',[frozen.id])).rows[0].v,false);
await db.query("select set_config('test.uid',$1,true)",[id(969)]);
assert.equal((await db.query('select invoice_month_close_candidate.approve($1) v',[frozen.id])).rows[0].v,true);
assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='approved'",[frozen.id])).rows[0].n,2);
await db.query('rollback');await db.query("select set_config('test.uid',$1,false)",[actor]);
for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query("select has_function_privilege($1,'invoice_month_close_candidate.preview_for_approver(uuid)','EXECUTE') v",[role])).rows[0].v,false);
console.log(JSON.stringify({fixture_two_approvers_including_worker:true,financial_core_not_public:true}));
await addExtras();assert.equal(await readiness(),'data_changed');await assert.rejects(db.query('select invoice_month_close_candidate.approve($1)',[frozen.id]),/invoice_not_ready/);
assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='pending'",[frozen.id])).rows[0].n,1);
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2020-10-25','2020-10-27')",[company,site]);
await db.query("update daily_reports set status='draft' where id=$1",[id(900)]);assert.equal(await readiness(),'report_pending');
await assert.rejects(db.query('select invoice_month_close_candidate.approve($1)',[frozen.id]),/invoice_not_ready/);
await db.query("update daily_reports set status='signed' where id=$1",[id(900)]);
if(process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL){
 const {connectFixture}=await import(process.argv[2]);const writer=await connectFixture();
 try{
  await writer.query('begin');await writer.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2020-10-22'",[company,site]);
  await assert.rejects(db.query('select invoice_month_close_candidate.approve($1)',[frozen.id]),/lock timeout/);
  await writer.query('rollback');
  assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='pending'",[frozen.id])).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int n from public.invoice_approval_audit where invoice_id=$1',[frozen.id])).rows[0].n,0);
  // Legacy attendance writer holds a row then runs the actual refresh, which
  // takes the invoice lock. Approval holds the invoice then waits on its gate.
  // The gate timeout must break the wait without partial approval.
  await writer.query("select set_config('test.uid',$1,false)",[actor]);
  await writer.query('begin');await writer.query("set local statement_timeout='2s'");
  await writer.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2020-10-22'",[company,site]);
  const pendingApproval=db.query('select invoice_month_close_candidate.approve($1)',[frozen.id]).then(()=>null,e=>e);
  await new Promise(resolve=>setTimeout(resolve,100));
  const pendingRefresh=writer.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2020-10-01']).then(()=>null,e=>e);
  const [approvalErr,refreshErr]=await Promise.all([pendingApproval,pendingRefresh]);assert.match(approvalErr?.message||'',/lock timeout/);assert.equal(refreshErr,null);
  await writer.query('rollback');
  assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='pending'",[frozen.id])).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int n from public.invoice_approval_audit where invoice_id=$1',[frozen.id])).rows[0].n,0);
  console.log(JSON.stringify({fixture_refresh_approval_cycle_timeout_safe:true}));
  console.log(JSON.stringify({fixture_approval_writer_conflict_fails_closed:true,fixture_approval_no_partial_write:true}));
 }finally{await writer.query('rollback').catch(()=>{});await writer.end();}
}
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
if(process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL){
 // Both sessions use synthetic IDs and commit only to the ephemeral fixture.
 await db.query('insert into public.invoice_approvers values($1,$2,2)',[company,id(969)]);await db.query('select private.ensure_invoice_approval_rows($1)',[frozen.id]);
 const {connectFixture}=await import(process.argv[2]);const a=await connectFixture(),b=await connectFixture();
 try{
  await a.query("select set_config('test.uid',$1,false)",[actor]);await b.query("select set_config('test.uid',$1,false)",[id(969)]);
  const calls=await Promise.all([a.query('select invoice_month_close_candidate.approve($1) v',[frozen.id]),b.query('select invoice_month_close_candidate.approve($1) v',[frozen.id])]);
  assert.deepEqual(calls.map(x=>x.rows[0].v).sort(),[false,true]);
  assert.equal((await db.query("select count(*)::int n from public.invoice_approvals where invoice_id=$1 and status='approved'",[frozen.id])).rows[0].n,2);
  const beforeSnapshot=(await db.query('select snapshot from invoices where id=$1',[frozen.id])).rows[0].snapshot;
  await db.query("update attendance_entries set overtime_hours=3 where company_id=$1 and site_id=$2 and work_date='2020-10-22'",[company,site]);
  await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2020-10-01']);
  assert.deepEqual((await db.query('select snapshot from invoices where id=$1',[frozen.id])).rows[0].snapshot,beforeSnapshot);
  console.log(JSON.stringify({fixture_concurrent_two_approvers_including_worker:true,fixture_late_edit_can_leave_approved_invoice_stale:true}));
 }finally{await a.end();await b.end();}
}
console.log(JSON.stringify({real_refresh_preview_gate_readiness:true,matching_snapshot_ready:true,late_extra_work_rejected:true,old_report_pending_rejected:true,original_unchanged_until_fixture_approval:true,route_source_stub:true,candidate_approval_ready_and_rollback:true,actual_public_approval_unchanged:true}));
`;
const marker='console.log(JSON.stringify({invoice_correction_preview:true';assert.equal(wrapper.split(marker).length,2);
wrapper=wrapper.replaceAll('2026-10-','2020-10-').replace("const original=await readFile(originalPath,'utf8');","const original=(await readFile(originalPath,'utf8')).replaceAll('2026-10-','2020-10-');").replace("const marker='let checks=0;'",()=>declarations+"const marker='let checks=0;'").replace(marker,()=>injection+marker);
const generated=resolve(root,'tool/verify_month_close_integration.generated.mjs');
try{await writeFile(generated,wrapper);const r=spawnSync(process.execPath,[generated,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(generated).catch(()=>{});}
