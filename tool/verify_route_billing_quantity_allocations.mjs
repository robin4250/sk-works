import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
await db.exec(`create schema private;create schema auth;create role anon;create role authenticated;grant usage on schema public,private,auth to authenticated,anon;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('test.allowed',true),'true')='true'$$;
create table company_members(company_id uuid,user_id uuid,role text);create table workers(id uuid,company_id uuid,name text);
create table customers(id uuid,company_id uuid,name text);create table sites(id uuid,company_id uuid,name text,customer_id uuid);
create table site_financial_settings(company_id uuid,site_id uuid,billing_unit_price_yen integer,billing_square_meter_unit_price_yen integer,billing_contract_amount_yen integer);
create table site_calculation_source_preferences(company_id uuid,site_id uuid,output_type text,source text,trade_company_id uuid);
create table trade_companies(id uuid,company_id uuid);
create table trade_company_contracts(company_id uuid,trade_company_id uuid,contract_method text,daily_rate_yen integer);
create table private.route_visit_reports(id uuid,company_id uuid,created_by uuid,report_date date,status text,roster_workers jsonb,site_id uuid,site_name text,source_clock_in_id uuid,start_capture_id uuid,end_capture_id uuid);
create table attendance_entries(id uuid,base_man_days numeric);create table invoices(id uuid,status text,snapshot jsonb);`);
await db.exec(await fs.readFile(new URL('../supabase/tests/route_customer_day_billing_allocations_schema.sql',import.meta.url),'utf8'));
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,worker,user,manager,employee,foreign,custA,custB,siteA,siteB,siteA2,reportA,reportB,reportA2]=Array.from({length:14},(_,i)=>id(i+1));
const json=x=>`'${JSON.stringify(x)}'::jsonb`;
await db.exec(`insert into company_members values('${company}','${user}','employee'),('${company}','${manager}','manager'),('${company}','${employee}','employee'),('${id(99)}','${foreign}','manager');insert into workers values('${worker}','${company}','本人');insert into customers values('${custA}','${company}','会社A'),('${custB}','${company}','会社B');insert into sites values('${siteA}','${company}','現場A','${custA}'),('${siteB}','${company}','現場B','${custB}'),('${siteA2}','${company}','現場A2','${custA}');insert into site_financial_settings values('${company}','${siteA}',20000,0,0),('${company}','${siteB}',25000,0,0),('${company}','${siteA2}',30000,0,0);insert into attendance_entries values('${id(90)}',1);insert into invoices values('${id(91)}','finalized','{"amount":12345}');`);
const insertReport=async(report,site,name,seed)=>db.exec(`insert into private.route_visit_reports values('${report}','${company}','${user}','2026-10-11','completed',${json([{worker_id:worker,worker_name:'本人'}])},'${site}','${name}','${id(seed)}','${id(seed+1)}','${id(seed+2)}')`);
await insertReport(reportA,siteA,'現場A',20);await insertReport(reportB,siteB,'現場B',30);await insertReport(reportA2,siteA2,'現場A2',40);
const rpc=async(sql)=>(await db.query(`select ${sql} v`)).rows[0].v;
const submit=(reports,alloc)=>rpc(`public.submit_route_customer_day_allocations('${worker}',array[${reports.map(v=>`'${v}'::uuid`).join(',')}],${json(alloc)})`);
const detail=req=>rpc(`public.route_billing_quantity_request_detail('${req.id}')`);
const decide=(req,qty=1,site=siteA,price=20000,version=req.version)=>rpc(`public.decide_route_billing_quantity('${req.id}',${qty},'approve','note',${version},'${site}',${price})`);
await db.exec(`set test.uid='${user}';set role authenticated`);
const rows=await submit([reportA,reportB],[{customer_id:custA,quantity:1},{customer_id:custB,quantity:1}]);assert.equal(rows.length,2);assert.deepEqual(rows[0].site_options,[]);assert.equal(Object.hasOwn(rows[0],'unit_price_yen'),false);assert.equal(rows.reduce((sum,r)=>sum+Number(r.quantity),0),2);
const a=rows.find(r=>r.customer_id===custA),b=rows.find(r=>r.customer_id===custB);
assert.equal((await submit([reportA,reportB],[{customer_id:custA,quantity:1},{customer_id:custB,quantity:1}]))[0].version,1);
await assert.rejects(decide(a),/manager approval required/);
await db.exec(`set test.uid='${employee}'`);await assert.rejects(detail(a),/unavailable/);
await db.exec(`set test.uid='${foreign}'`);await assert.rejects(decide(a),/manager approval required/);
await db.exec(`set test.uid='${manager}'`);assert.equal((await rpc('public.pending_route_billing_quantity_rows()')).length,2);
await assert.rejects(decide(a,1,siteB,25000),/evidenced/);await assert.rejects(decide(a,0.2),/explicit quantity/);
// Invoice-selected trade company rate overrides site rate; fixed contracts cannot be approved as days.
await db.exec('reset role');await db.exec(`insert into trade_companies values('${id(80)}','${company}');insert into trade_company_contracts values('${company}','${id(80)}','daily',42000);insert into site_calculation_source_preferences values('${company}','${siteA}','invoice','trade_company','${id(80)}');set role authenticated`);
assert.equal((await detail(a)).site_options[0].unit_price_yen,42000);assert.equal((await detail(a)).site_options[0].man_day_method,true);
for (const method of ['monthly','square_meter','contract','none']) {
 await db.exec('reset role');await db.exec(`update trade_company_contracts set contract_method='${method}';set role authenticated`);
 assert.equal((await detail(a)).site_options[0].man_day_method,false);await assert.rejects(decide(a),/evidenced/);
}
await db.exec('reset role');await db.exec(`update trade_company_contracts set contract_method='daily',daily_rate_yen=0;set role authenticated`);
assert.equal((await detail(a)).site_options[0].man_day_method,false);await assert.rejects(decide(a),/evidenced/);
// A site daily rate takes precedence over old fixed fields, just as the invoice does.
await db.exec('reset role');await db.exec(`update site_calculation_source_preferences set source='site';update site_financial_settings set billing_contract_amount_yen=99999 where site_id='${siteA}';set role authenticated`);
assert.equal((await detail(a)).site_options[0].unit_price_yen,20000);assert.equal((await detail(a)).site_options[0].man_day_method,true);
await assert.rejects(db.query(`select * from private.route_billing_site_daily_rate('${company}','${siteA}')`),/permission denied/);
const approved=await decide(a);assert.equal(approved.status,'approved');assert.equal((await decide(a)).status,'approved');
await decide(b,0.5,siteB,25000);
await db.exec(`set test.uid='${user}'`);const revised=(await submit([reportA,reportA2],[{customer_id:custA,quantity:1}]))[0];assert.equal(revised.status,'pending');assert.equal(revised.version,2);assert.equal(revised.unit_price_yen,undefined);assert.deepEqual(revised.site_options,[]);assert.equal(Object.hasOwn(revised,'unit_price_yen'),false);
await db.exec(`set test.uid='${manager}'`);assert.equal((await detail(a)).site_options.length,2);await assert.rejects(decide(a),/request changed/);await decide(revised,1,siteA2,30000);
// Current evidence/customer reassignment invalidates stale approval.
await db.exec('reset role');await db.exec(`update sites set customer_id='${custB}' where id='${siteA}'`);await db.exec(`set test.uid='${user}';set role authenticated`);
await submit([reportA2],[{customer_id:custA,quantity:0.5}]);const pending=await detail(a);await db.exec(`set test.uid='${manager}'`);await assert.rejects(decide(pending,0.5,siteA2,30000),/customer evidence changed/);
await assert.rejects(db.query('select * from private.route_billing_quantity_requests'),/permission denied/);
await db.exec('reset role');assert.equal((await db.query('select base_man_days from attendance_entries')).rows[0].base_man_days,'1');assert.deepEqual((await db.query('select snapshot from invoices')).rows[0].snapshot,{amount:12345});assert.equal((await db.query('select count(*)::int n from private.route_billing_quantity_requests')).rows[0].n,2);
await db.exec('set role anon');await assert.rejects(rpc('public.pending_route_billing_quantity_rows()'),/permission denied/);
console.log('PASS allocation roles, two companies total2, retries, evidenced rate selection, revision stale rejection, current-customer guard, canonical attendance/finalized invoice untouched');await db.close();
