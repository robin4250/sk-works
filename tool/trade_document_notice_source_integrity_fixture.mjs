// Isolated bridge to the pinned real source hash/revalidators/catalog guards.
// This does not run the complete source calculator or establish live Auth.
import fs from 'node:fs/promises';
export async function verifyNoticeSourceIntegrity(db,c){
 const {A,B,UA,id,q,check,deny,pending}=c;
 await db.exec("set timezone='UTC'");
 const source=await fs.readFile(process.env.SKO_NOTICE_SOURCE_PREVIEW,'utf8');
 const core=await fs.readFile(process.env.SKO_NOTICE_APPROVER_CORE,'utf8');
 // Empty dependencies are explicit fixtures. Existing financial/attendance rows
 // stay in place; no actual production schema or source data is loaded.
 await db.exec(`create schema if not exists document_adjustment_private;
 create schema if not exists invoice_correction_preview_private;
 create table if not exists public.site_financial_settings(company_id uuid);
 create table if not exists public.site_calculation_source_preferences(company_id uuid);
 create table if not exists public.trade_company_contracts(company_id uuid);
 create table if not exists public.route_stops(company_id uuid);
 create table if not exists private.route_visit_reports(company_id uuid);
 create table if not exists private.route_journey_captures(id uuid,company_id uuid);
 create table if not exists private.route_journey_visit_events(capture_id uuid);
 create table if not exists private.route_billing_quantity_evidence(request_id uuid);
 create table if not exists private.expense_claims(company_id uuid);
 create table if not exists private.expense_settlement_choices(company_id uuid);
 create table if not exists private.expense_amount_consumptions(company_id uuid);
 create table if not exists document_adjustment_private.rollout(company_id uuid);
 create table if not exists document_adjustment_private.templates(id uuid,company_id uuid);
 create table if not exists document_adjustment_private.template_versions(template_id uuid);
 create table if not exists document_adjustment_private.occurrences(template_id uuid);`);
 await db.exec('alter table private.route_billing_quantity_requests add column if not exists id uuid');
 const name='invoice_correction_preview_private.source_fingerprint';
 const start=source.indexOf('create function '+name+'(');
 const end=source.indexOf('revoke all on function '+name+'(',start);
 if(start<0||end<start)throw Error('pinned source fingerprint anchor absent');
 await db.exec(source.slice(start,end));
 const fingerprint=()=>q('select invoice_correction_preview_private.source_fingerprint($1) v',[A]);
 const before=await fingerprint();check(/^[a-f0-9]{64}$/.test(before),true);
 check(await fingerprint(),before);
 await db.exec('begin');
 try{
  await db.query('insert into public.attendance_entries values($1,$2,$3,$4,$5)',[B,UA,id(49999),'2020-10-20',id(49998)]);
  check(await fingerprint(),before);
 }finally{await db.exec('rollback');}
 // Replace every unconditional core-integrity/preview/revalidation fixture by
 // the existing exact generator output. Full calculator execution remains in
 // its separate suite; here the genuine revalidators and hash guards are run.
 await db.exec(`drop function invoice_month_close_candidate.approver_core_intact();
 drop function invoice_month_close_candidate.notice_core_intact();
 drop function invoice_month_close_candidate.preview_for_approver(uuid);
 drop function invoice_month_close_candidate.preview_for_notice(uuid,uuid);
 drop function invoice_month_close_candidate.revalidate_for_approver(uuid,text,text);
 drop function invoice_month_close_candidate.revalidate_for_notice(uuid,uuid,text,text);`);
 await db.exec(core);
 check(await q('select invoice_month_close_candidate.approver_core_intact() v'),true);
 check(await q('select invoice_month_close_candidate.notice_core_intact() v'),true);
 await (await import('./trade_document_notice_daily_preview_fixture.mjs')).verifyNoticeDailyPreview(db,c);
 const prepareNamed=await (await import('./trade_document_notice_adjustment_provider_fixture.mjs')).installNoticeAdjustmentProvider(db,c);
 const prepareExpense=await (await import('./trade_document_notice_expense_provider_fixture.mjs')).installNoticeExpenseProvider(db,c);
 const prepareRoute=await (await import('./trade_document_notice_route_provider_fixture.mjs')).installNoticeRouteProvider(db,c);
 const fp=await fingerprint();
 const original=await q("select encode(sha256(convert_to(to_jsonb(i)::text,'UTF8')),'hex') v from public.invoices i where id=$1",[pending.parent]);
 await db.query('select invoice_month_close_candidate.revalidate_for_approver($1,$2,$3)',[pending.parent,fp,original]);
 await db.query('select invoice_month_close_candidate.revalidate_for_notice($1,$2,$3,$4)',[pending.parent,UA,fp,original]);
 await db.exec('begin');
 try{
  await db.query('update public.attendance_entries set source_report_id=null where company_id=$1',[A]);
  check((await fingerprint())===fp,false);
  await deny(()=>db.query('select invoice_month_close_candidate.revalidate_for_notice($1,$2,$3,$4)',[pending.parent,UA,fp,original]),/invoice_revision_stale/);
 }finally{await db.exec('rollback');}
 check(await fingerprint(),fp);
 await (await import('./trade_document_notice_calculated_confirmation_fixture.mjs')).verifyCalculatedNoticeConfirmation(db,c);
 await (await import('./trade_document_notice_calculated_confirmation_fixture.mjs')).verifyCalculatedNoticeConfirmation(db,c,prepareNamed,'named-adjustment');
 await (await import('./trade_document_notice_calculated_confirmation_fixture.mjs')).verifyCalculatedNoticeConfirmation(db,c,async()=>{await prepareNamed();await prepareExpense();},'named-adjustment-and-expense');
 await (await import('./trade_document_notice_calculated_confirmation_fixture.mjs')).verifyCalculatedNoticeConfirmation(db,c,async()=>{await prepareNamed();await prepareExpense();await prepareRoute();},'named-adjustment-expense-and-route');
 // A forged replacement cannot keep the actual integrity guard ready even
 // when a caller supplies a proposal or ticket matching the financial parent.
 await db.exec(`create or replace function invoice_month_close_candidate.preview_for_approver(p_invoice_id uuid) returns jsonb language plpgsql as $$begin return '{}'::jsonb;end$$;`);
 check(await q('select invoice_month_close_candidate.approver_core_intact() v'),false);
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'source_proof_missing');
 await db.exec(`create or replace function invoice_month_close_candidate.preview_for_notice(p_invoice_id uuid,p_recipient uuid) returns jsonb language plpgsql as $$begin return '{}'::jsonb;end$$;`);
 check(await q('select invoice_month_close_candidate.notice_core_intact() v'),false);
 check(await q('select invoice_month_close_candidate.notification_readiness($1,$2) v',[pending.parent,UA]),{status:'unavailable'});
 console.log('PASS pinned real source hash/revalidators/core guards; all-source calculator and GoTrue remain incomplete; actual daily financial composition verified separately');
}
