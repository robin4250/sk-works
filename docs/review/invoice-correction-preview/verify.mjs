import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(process.env.SKO_ADJUSTMENT_ROOT||'../doc-adjustment-buttons-candidate');
const originalPath=resolve(root,'tool/verify_adjustment_real_refresh.mjs');
const original=await readFile(originalPath,'utf8');
const candidate=await readFile(resolve(process.env.SKO_PREVIEW_SQL||'../invoice-correction-preview-candidate/preview.sql.review-only'),'utf8');
const marker='let checks=0;';assert.equal(original.split(marker).length,2);
const payload=`
// Only isolated, synthetic fixture data. Preserve the invoice/approval record.
await db.exec("create or replace function private.has_company_feature(p_company uuid,p_feature text) returns boolean language sql as $$select true$$;");
await db.exec(${JSON.stringify(candidate)});
await db.exec("create table if not exists private.route_journey_captures(id uuid,company_id uuid); create table if not exists private.route_journey_visit_events(capture_id uuid); create table if not exists public.invoice_approval_audit(invoice_id uuid,company_id uuid); create table if not exists public.daily_reports(id uuid,company_id uuid); create table if not exists public.daily_report_workers(report_id uuid); create table if not exists public.route_stops(company_id uuid); create table if not exists private.route_billing_quantity_requests(id uuid,company_id uuid); create table if not exists private.route_billing_quantity_evidence(request_id uuid); create table if not exists private.expense_amount_consumptions(company_id uuid);");
await db.query("update site_financial_settings set billing_allowance_1_name='合成手当',billing_allowance_1_amount_yen=10,billing_overtime_hour_rate_yen=20 where company_id=$1 and site_id=$2",[company,site]);

// Existing approved route allocation, accepted extra expense and one adjustment
// are present before both original and corrected views are built.
const routeSite=id(104),routeReport=id(105),routeStart=id(106),routeCap1=id(107),routeCap2=id(108),expenseId=id(109);
await db.query("update attendance_entries set work_date='2026-10-16',work_category=null where company_id=$1 and site_id=$2 and work_date='2026-10-01'",[company,site]);
await db.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-22','day',1),($1,$2,$3,'2026-10-24','day',1),($1,$2,$3,'2026-10-26','day',1)",[company,site,worker]);

await db.query("insert into sites(id,company_id,customer_id,name) values($1,$2,$3,'合成ルート現場')",[routeSite,company,customer]);
await db.query('insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,150,5)',[company,routeSite]);
await db.query("insert into private.route_visit_reports(id,company_id,created_by,report_date,status,workers,roster_workers,site_id,site_name,source_clock_in_id,start_capture_id,end_capture_id) values($1,$2,$3,'2026-10-12','completed',$4::jsonb,$4::jsonb,$5,'合成ルート現場',$6,$7,$8)",[routeReport,company,actor,JSON.stringify([{worker_id:worker,worker_name:'合成社員'}]),routeSite,routeStart,routeCap1,routeCap2]);
const routeRows=(await db.query('select public.submit_route_customer_day_allocations($1,$2::uuid[],$3::jsonb) v',[worker,[routeReport],JSON.stringify([{customer_id:customer,quantity:1}])])).rows[0].v;
await db.query("select public.decide_route_billing_quantity($1,1,'approve','',1,$2,150)",[routeRows[0].id,routeSite]);
await db.query("insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision) values($1,$2,$3,'合成社員',$4,'2026-10-01','合成経費',4,'approved','customer',$5,2)",[expenseId,company,worker,actor,customer]);
await db.query("insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current) values($1,$2,'cash','2026-10-01',2,$3,true,true)",[expenseId,company,actor]);
const adjustmentCommand={command_id:crypto.randomUUID(),company_id:company,kind:'invoice',party_id:customer,month:'2026-10-01',expected_version:0,action:'add',entry_id:null,sign:'plus',title:'合成追加',amount_yen:10,recurrence:'once',effective_month:'2026-10-01',calculation_mode:'settlement_yen',site_id:null,expected_template_version:null,update_scope:'current_month'};
const adjustmentPreview=(await db.query('select public.preview_trade_document_adjustment($1) v',[JSON.stringify(adjustmentCommand)])).rows[0].v;
await db.query('select public.apply_trade_document_adjustment($1,$2) v',[JSON.stringify(adjustmentCommand),adjustmentPreview.token]);
await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
const addExtras=()=>db.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,'2026-10-25','day',1,0,0,ARRAY['合成手当']),($1,$2,$3,'2026-10-27','day',1,1,0,ARRAY['合成手当'])",[company,site,worker]);
await addExtras();await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
const expected=(await db.query('select snapshot,subtotal,tax,welfare_amount,grand_total from invoices where company_id=$1 and customer_id=$2',[company,customer])).rows[0];
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2026-10-25','2026-10-27')",[company,site]);
await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
await db.query("update invoices set status='finalized',finalized_at=now() where company_id=$1 and customer_id=$2",[company,customer]);
await db.query("update invoices set status='draft',finalized_at=null where company_id=$1 and customer_id=$2",[company,customer]);
const frozen=(await db.query('select * from invoices where company_id=$1 and customer_id=$2',[company,customer])).rows[0];assert.equal(frozen.invoice_seal_frozen,true);
await addExtras();await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
const correctionPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
assert.match(correctionPreview.source_fingerprint,/^[0-9a-f]{64}$/);assert.match(correctionPreview.original_invoice_fingerprint,/^[0-9a-f]{64}$/);
const unchangedPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.equal(unchangedPreview.source_fingerprint,correctionPreview.source_fingerprint);
await db.query("update private.route_visit_reports set site_name='合成変更' where id=$1",[routeReport]);
const routeChanged=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.notEqual(routeChanged.source_fingerprint,correctionPreview.source_fingerprint);
await db.query("update private.route_visit_reports set site_name='合成ルート現場' where id=$1",[routeReport]);
await db.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
const changedPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.notEqual(changedPreview.source_fingerprint,correctionPreview.source_fingerprint);
await db.query("update attendance_entries set overtime_hours=1 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
assert.ok(expected.snapshot.sites.some(item=>item.route_billing_request_id));assert.equal(expected.snapshot.expense_extra_amount_yen,4);assert.equal(expected.snapshot.document_adjustments_v1.length,1);assert.equal(Object.hasOwn(correctionPreview.proposed_snapshot,'company_seal_snapshot'),false);
await db.query("update company_members set role='worker' where company_id=$1 and user_id=$2",[company,actor]);await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_not_allowed/);await db.query("update company_members set role='admin' where company_id=$1 and user_id=$2",[company,actor]);
const oldSite=frozen.snapshot.sites.find(item=>item.site_id===site);const newSite=correctionPreview.proposed_snapshot.sites.find(item=>item.site_id===site);
assert.equal(Number(oldSite.lines[0].quantity),4);assert.equal(Number(newSite.lines[0].quantity),6);
assert.equal(Number(frozen.snapshot.sites.find(item=>item.route_billing_request_id).lines[0].quantity),1);assert.equal(Number(correctionPreview.proposed_snapshot.sites.find(item=>item.route_billing_request_id).lines[0].quantity),1);
const expectedSnapshot={...expected.snapshot};delete expectedSnapshot.company_seal_snapshot;
assert.deepEqual(correctionPreview.proposed_snapshot,expectedSnapshot);assert.equal(correctionPreview.subtotal,expected.subtotal);assert.equal(correctionPreview.tax,expected.tax);assert.equal(correctionPreview.welfare,expected.welfare_amount);assert.equal(correctionPreview.grand_total,expected.grand_total);
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
await db.query('update site_financial_settings set billing_unit_price_yen=billing_unit_price_yen+1 where company_id=$1 and site_id=$2',[company,site]);
await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_saved_basis_changed/);
await db.query('update site_financial_settings set billing_unit_price_yen=billing_unit_price_yen-1 where company_id=$1 and site_id=$2',[company,site]);
const originalRefresh=(await db.query("select pg_get_functiondef('private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure) v")).rows[0].v;
const changedRefresh=originalRefresh.replace('declare'+String.fromCharCode(10),'declare'+String.fromCharCode(10)+' -- synthetic calculator drift'+String.fromCharCode(10));assert.notEqual(changedRefresh,originalRefresh);
await db.exec(changedRefresh);await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_calculator_changed/);
await db.exec(originalRefresh);

console.log(JSON.stringify({invoice_correction_preview:true,real_refresh_equality:true,original_frozen_unchanged:true,saved_price_drift_rejected:true,route_expense_adjustment_equality:true,unauthorized_denied:true,synthetic_five_to_seven_days:true}));await db.close();process.exit(0);
`;
const generated=resolve(root,'tool/verify_correction_preview.generated.mjs');
try {await writeFile(generated,original.replace(marker,()=>payload+marker).replace('error:error.message,where:error.where','error:error.message,where:error.where,query:error.query?.slice(0,1500)'));const r=spawnSync(process.execPath,[generated,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(generated).catch(()=>{});}
