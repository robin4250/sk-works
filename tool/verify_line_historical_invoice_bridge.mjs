import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {pathToFileURL} from 'node:url';
process.on('uncaughtException',error=>{console.error(error.message,error.code,error.internalQuery ?? '');process.exit(1);});
import {prepareBridgeFixture,makeBridgeQuote,id} from './fixtures/line_historical_invoice_bridge_fixture.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);const db=new PGlite();
try {
 await prepareBridgeFixture(db);
 const functions=async()=> (await db.query("select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' name,md5(pg_get_functiondef(p.oid)) hash,p.proacl::text acl,p.proconfig::text path,p.proowner::regrole::text owner from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f' order by 1")).rows;
 const triggers=async()=> (await db.query("select tgname,pg_get_triggerdef(oid) definition from pg_trigger where tgrelid='invoices'::regclass and not tgisinternal order by 1")).rows;
 const oldFunctions=await functions(),oldTriggers=await triggers();
 await db.exec(readFileSync('supabase/migrations/20261013003917_line_historical_invoice_bridge.sql','utf8'));
 const after=await functions();for(const f of oldFunctions)assert.deepEqual(after.find(x=>x.name===f.name),f);assert.deepEqual(await triggers(),oldTriggers);assert.equal(oldTriggers.length,9);
 const quote=await makeBridgeQuote(db,'2020-01-01',200);
 const q=async(sql,params=[])=> (await db.query(sql,params)).rows[0]?.value;
 const historyBefore=await q("select md5(jsonb_agg(to_jsonb(q))::text) value from private.line_historical_quote_snapshots q");
 const preview=async(terms=quote.terms,tax=1000,confirmed=true,fp=quote.fingerprint)=>q('select public.line_historical_invoice_preview($1,$2,$3,$4,$5) value',[quote.id,fp,JSON.stringify(terms),tax,confirmed]);
 await assert.rejects(preview(quote.terms,null),/Explicit historical/);await assert.rejects(preview(quote.terms,1000,false),/Explicit historical/);
 await assert.rejects(preview([{...quote.terms[0],welfare_rate_bps:null}]),/Confirm historical/);
 await assert.rejects(preview([{...quote.terms[0],customer_id:id(72)}]),/Confirm historical/);await assert.rejects(preview([{...quote.terms[0],customer_id:id(73)}]),/Confirm historical/);
 await assert.rejects(preview(quote.terms,1000,true,'stale'),/Historical quote changed/);
 await db.query(`insert into private.expense_claims values($1,$2,1,'2020-01-01','customer',$3,'approved',false,$4,'本人','保存経費',500)`,[id(300),id(10),id(70),id(2)]);
 await db.query(`insert into private.expense_settlement_choices values($1,$2,'reimbursement','2020-01-01',true,true)`,[id(300),id(10)]);
 const p=await preview();assert.equal(p.historical_base_subtotal,23000);assert.equal(p.people,1);assert.equal(p.man_days,2);
 const invoice=p.quotes[0];assert.equal(invoice.subtotal,24150);assert.equal(invoice.welfare,1150);assert.equal(invoice.tax,2415);assert.equal(invoice.expense_extra_amount_yen,500);assert.equal(invoice.grand_total,27065);assert.equal(invoice.sites[0].site_name,'履歴現場A');assert.equal(invoice.sites[0].lines[0].unit_price,10000);
 await db.exec('update companies set tax_rate=80;update site_financial_settings set billing_unit_price_yen=99999,welfare_rate=90');assert.deepEqual(await preview(),p);
 const zero=await preview([{...quote.terms[0],welfare_rate_bps:0}],0);assert.equal(zero.quotes[0].tax,0);assert.equal(zero.quotes[0].welfare,0);assert.equal(zero.quotes[0].grand_total,23500);
 const create=async(command=201,terms=quote.terms,fp=p.fingerprint,confirmed=true)=>q('select public.create_line_historical_invoices($1,$2,$3,$4,1000,true,$5,$6) value',[id(command),quote.id,quote.fingerprint,JSON.stringify(terms),fp,confirmed]);
 await assert.rejects(create(201,quote.terms,p.fingerprint,false),/Confirm the displayed/);
 await db.exec('update private.expense_claims set amount_yen=600,revision=2');await assert.rejects(create(),/saved expenses changed/);assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,0);
 await db.exec('update private.expense_claims set amount_yen=500,revision=1');
 const created=await create();assert.equal(created.status,'draft');assert.equal(created.issued,false);assert.equal(created.approved,false);assert.deepEqual(await create(),created);
 await assert.rejects(create(201,[{...quote.terms[0],welfare_rate_bps:0}]),/Command content changed/);
 await assert.rejects(create(202,[{...quote.terms[0],customer_id:id(71)}],(await preview([{...quote.terms[0],customer_id:id(71)}])).fingerprint),/LINE month already converted/);
 const saved=(await db.query('select * from invoices where id=$1',[created.invoices[0].invoice_id])).rows[0];assert.equal(saved.status,'draft');assert.equal(saved.automatic_calculation,false);assert.equal(saved.finalized_at,null);assert.equal(saved.approval_finalized_at,null);assert.equal(saved.snapshot.line_historical_quote_evidence.quote_id,quote.id);assert.equal(saved.snapshot.company_seal_snapshot.fixture,'retained');assert.equal(saved.snapshot.expense_extra_amount_yen,500);
 assert.equal(await q("select md5(jsonb_agg(to_jsonb(q))::text) value from private.line_historical_quote_snapshots q"),historyBefore);assert.equal((await db.query('select count(*)::int n from attendance_entries')).rows[0].n,0);assert.equal((await db.query('select count(*)::int n from attendance_correction_requests')).rows[0].n,0);assert.deepEqual((await db.query('select payload from payroll_statements')).rows,[{payload:{saved:'unchanged'}}]);

 const expensePreview=()=>q('select public.line_historical_invoice_expense_preview($1,$2) value',[quote.id,saved.id]);
 const refresh=fp=>q('select public.refresh_line_historical_invoice_expenses($1,$2,$3,true) value',[quote.id,saved.id,fp]);
 await db.query("insert into invoice_approvals values($1,'approved')",[saved.id]);await assert.rejects(expensePreview(),/edited or finalized/);await db.query('delete from invoice_approvals where invoice_id=$1',[saved.id]);
 await db.query('update invoices set grand_total=grand_total+1 where id=$1',[saved.id]);await assert.rejects(expensePreview(),/edited or finalized/);await db.query('update invoices set grand_total=$2 where id=$1',[saved.id,saved.grand_total]);
 await db.query("insert into invoice_approvals values($1,'pending')",[saved.id]);
 const oldExpensePreview=await expensePreview();await db.exec('update private.expense_claims set amount_yen=600,revision=2');await assert.rejects(refresh(oldExpensePreview.fingerprint),/expenses changed/);
 const freshExpensePreview=await expensePreview();assert.equal(freshExpensePreview.grand_total,27165);assert.equal(freshExpensePreview.expense_extra_amount_yen,600);await q('select public.refresh_line_historical_invoice_expenses($1,$2,$3,null) value',[quote.id,saved.id,freshExpensePreview.fingerprint]);assert.equal((await db.query('select grand_total from invoices where id=$1',[saved.id])).rows[0].grand_total,27065);const refreshResult=await refresh(freshExpensePreview.fingerprint);assert.deepEqual(await refresh(freshExpensePreview.fingerprint),refreshResult);
 const refreshed=(await db.query('select * from invoices where id=$1',[saved.id])).rows[0];assert.equal(refreshed.grand_total,27165);assert.deepEqual(refreshed.snapshot.sites,saved.snapshot.sites);assert.deepEqual(refreshed.snapshot.line_historical_quote_evidence,saved.snapshot.line_historical_quote_evidence);assert.equal(refreshed.tax,saved.tax);assert.equal(refreshed.welfare_amount,saved.welfare_amount);assert.equal(refreshed.adjustments,0);
 await db.exec('update private.expense_claims set amount_yen=500,revision=1');await refresh((await expensePreview()).fingerprint);
 await assert.rejects(q('select public.line_historical_invoice_expense_preview($1,$2) value',[quote.id,id(999)]),/Bridge invoice unavailable/);

 // Current stage-two creation cannot duplicate the historical month at a new customer.
 await db.query('update sites set customer_id=$1',[id(71)]);const legacy=await q('select public.line_invoice_preview($1,1) value',[quote.draft]);
 await assert.rejects(q('select public.create_line_invoices($1,$2,1,$3) value',[id(203),quote.draft,legacy.fingerprint]),/Historical LINE month already converted/);assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,1);
 // Existing finalization hooks still refuse stale expense recovery and route quantities.
 await db.exec('update private.expense_claims set amount_yen=600,revision=2');await assert.rejects(db.query('update invoices set approval_finalized_at=now() where id=$1',[saved.id]),/経費が更新/);
 await db.exec("update private.expense_claims set amount_yen=500,revision=1;set test.route_blocked='true'");await assert.rejects(db.query('update invoices set approval_finalized_at=now() where id=$1',[saved.id]),/Route quantity incomplete/);await db.exec("set test.route_blocked='false'");
 await db.query('update invoices set approval_finalized_at=now() where id=$1',[saved.id]);await assert.rejects(expensePreview(),/edited or finalized/);assert.equal((await db.query('select count(*)::int n from private.expense_amount_consumptions')).rows[0].n,1);
 await db.query("select set_config('test.uid',$1,false)",[id(2)]);await assert.rejects(q('select public.line_historical_invoice_workspace($1) value',[quote.id]),/Master access required/);
 await db.exec('grant usage on schema private to authenticated;set role authenticated');await assert.rejects(db.query('select * from private.line_historical_invoice_commands'),/permission denied/);await assert.rejects(db.query('select * from private.line_historical_invoice_links'),/permission denied/);await db.exec('reset role;set role anon');await assert.rejects(q('select public.line_historical_invoice_workspace($1) value',[quote.id]),/permission denied/);await db.exec('reset role');
 await db.query("select set_config('test.uid',$1,false)",[id(1)]);
 const multi=await makeBridgeQuote(db,'2019-01-01',220,true);
 const multiPreview=await q('select public.line_historical_invoice_preview($1,$2,$3,1000,true) value',[multi.id,multi.fingerprint,JSON.stringify(multi.terms)]);assert.equal(multiPreview.quotes.length,2);
 await db.query(`insert into invoices(company_id,customer_id,billing_period_start,billing_period_end,status,snapshot) values($1,$2,'2019-01-01','2019-01-31','draft','{}')`,[id(10),id(71)]);
 const multiCreate=()=>q('select public.create_line_historical_invoices($1,$2,$3,$4,1000,true,$5,true) value',[id(221),multi.id,multi.fingerprint,JSON.stringify(multi.terms),multiPreview.fingerprint]);
 await assert.rejects(multiCreate(),/invoice already exists/);assert.equal((await db.query("select count(*)::int n from invoices where billing_period_start='2019-01-01'")).rows[0].n,1);assert.equal((await db.query('select count(*)::int n from private.line_historical_invoice_commands where quote_id=$1',[multi.id])).rows[0].n,0);
 await db.exec("delete from invoices where billing_period_start='2019-01-01'");const multiple=await multiCreate();assert.equal(multiple.invoices.length,2);assert.equal((await db.query("select count(*)::int n from invoices where billing_period_start='2019-01-01'")).rows[0].n,2);
 console.log('Historical invoice bridge: explicit parties/tax/welfare, frozen rates, saved expense preview, drift rejection, immutable retry, duplicate guards, nine retained invoice triggers, expense/route finalization, deny-by-default and no payroll/attendance changes passed.');
} finally {await db.close();}
