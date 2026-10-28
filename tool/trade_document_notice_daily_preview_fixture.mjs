// Actual pinned daily-price preview over synthetic closed-month source rows.
// Empty route/expense/adjustment providers remain explicit fixture boundaries.
import fs from 'node:fs/promises';
export async function verifyNoticeDailyPreview(db,c){
 const {A,UA,id,q,check,pending}=c;
 const columns={
  'document_adjustment_private.rollout':['enabled boolean default false'],
  'public.companies':['tax_rate numeric default 10'],
  'public.customers':['notes text'],
  'public.invoices':['automatic_calculation boolean default true'],
  'public.sites':['name text','formal_name text','created_at timestamptz default now()'],
  'public.attendance_entries':['work_category text default \'day\'','base_man_days numeric default 1','overtime_hours numeric default 0','early_hours numeric default 0','allowance_names text[] default \'{}\''],
  'public.site_financial_settings':['site_id uuid','billing_unit_price_yen numeric default 0','billing_monthly_rate_yen numeric default 0','billing_square_meter_unit_price_yen numeric default 0','billing_square_meter_quantity numeric default 0','billing_contract_amount_yen numeric default 0','billing_overtime_hour_rate_yen numeric default 0','billing_early_hour_rate_yen numeric default 0','billing_rate_formula jsonb default \'{}\'','billing_rate_overrides jsonb default \'{}\'','welfare_rate numeric default 0','billing_allowance_1_name text','billing_allowance_1_amount_yen numeric default 0','billing_allowance_2_name text','billing_allowance_2_amount_yen numeric default 0','billing_allowance_3_name text','billing_allowance_3_amount_yen numeric default 0'],
  'public.site_calculation_source_preferences':['site_id uuid','trade_company_id uuid','output_type text','source text'],
  'public.trade_company_contracts':['trade_company_id uuid','contract_method text','daily_rate_yen numeric','monthly_rate_yen numeric','square_meter_unit_price_yen numeric','square_meter_quantity numeric','contract_amount_yen numeric'],
 };
 for(const [table,fields]of Object.entries(columns))for(const field of fields)await db.exec(`alter table ${table} add column if not exists ${field}`);
 const label=await fs.readFile('supabase/migrations/20261008035509_invoice_registered_method_amounts_and_formula_labels.sql','utf8');
 await db.exec(label.slice(0,label.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice')));
 await db.exec(await fs.readFile('supabase/migrations/20261006180455_fix_rate_formula_combined_multipliers.sql','utf8'));
 const install=await fs.readFile('supabase/review/document_adjustment_install.incomplete.sql','utf8');
 const refreshStart=install.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_invoice(');
 const refreshEnd=install.indexOf('\n$function$',install.indexOf('AS $function$',refreshStart));
 if(refreshStart<0||refreshEnd<refreshStart)throw Error('existing refresh source anchor missing');
 await db.exec(install.slice(refreshStart,refreshEnd+'\n$function$'.length)+';');
 check(await q("select md5(prosrc) v from pg_proc where oid='private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure"),'00cf0c91a9430f50c9734fadcf37ec52');
 // Deliberately empty providers: this exercises the actual basic daily-price
 // branch, not real route attribution, expense settlement or named adjustments.
 await db.exec(`create function document_adjustment_private.active_items(uuid,text,uuid,date) returns jsonb language sql as $$select '[]'::jsonb$$;
 create function private.route_billing_invoice_components(uuid,uuid,date,date) returns jsonb language sql as $$select '{"blocked":false,"sites":[],"subtotal":0,"tax":0,"welfare":0,"has_requests":false,"source_issues":[]}'::jsonb$$;
 create function private.expense_cost_components(text,uuid,uuid,date,date,uuid) returns jsonb language sql as $$select '{"amount_yen":0,"has_choices":false,"claims":[]}'::jsonb$$;`);
 const customer=id(48000),site=id(40000+Number(pending.parent.slice(-4)));
 await db.query("insert into public.customers(id,company_id,name) values($1,$2,'合成日単価取引先')",[customer,A]);
 await db.query("update public.sites set customer_id=$1,name='合成日単価現場' where id=$2",[customer,site]);
 await db.query('insert into public.site_financial_settings(company_id,site_id,billing_unit_price_yen) values($1,$2,100000)',[A,site]);
 await db.query('update public.invoices set customer_id=$1,snapshot=$2::jsonb where id=$3',[customer,JSON.stringify({tax_rate_bps:1000,sites:[]}),pending.parent]);
 const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
 check(proposal.subtotal,100000);check(proposal.tax,10000);check(proposal.grand_total,110000);
 check(proposal.proposed_snapshot.sites[0].lines[0].quantity,1);
 // Save exactly the recalculated snapshot in the disposable fixture. The real
 // guard now compares an actual calculator proposal, not fixture_proposals.
 await db.query('update public.invoices set snapshot=$1::jsonb,subtotal=$2,tax=$3,welfare_amount=$4,grand_total=$5 where id=$6',[JSON.stringify(proposal.proposed_snapshot),proposal.subtotal,proposal.tax,proposal.welfare,proposal.grand_total,pending.parent]);
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 check((await q('select invoice_month_close_candidate.notification_readiness($1,$2) v',[pending.parent,UA])).status,'ready');
 // A later source day changes the real recalculation; a ready result must not
 // survive merely because the saved invoice and notice revision were unchanged.
 await db.exec('begin');
 try{
  await db.query("insert into public.attendance_entries(company_id,worker_id,site_id,work_date,source_report_id) select company_id,worker_id,site_id,work_date,source_report_id from public.attendance_entries where site_id=$1",[site]);
  check((await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent])).grand_total,220000);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'data_changed');
 }finally{await db.exec('rollback');}
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 console.log('PASS actual daily source preview -> real notice/approval readiness; empty downstream providers, no financial publication');
}
