// Existing source/rate/component readers over disposable route rows only.
import fs from 'node:fs/promises';
export async function installNoticeRouteProvider(db,c){
 const {A,B,UA,id,q,check,pending}=c;
 const fields={
  'public.attendance_entries':['route_assignment_id uuid'],
  'public.daily_reports':['signature_json jsonb'],
  'public.route_stops':['id uuid','route_assignment_id uuid','site_id uuid'],
  'private.route_journey_captures':['source_clock_in_id uuid','route_assignment_id uuid','work_date date','worker_id uuid','route_stop_id uuid','recorded_at timestamptz'],
  'private.route_journey_visit_events':['source_clock_in_id uuid','kind text','start_capture_id uuid','route_stop_id uuid'],
  'private.route_billing_quantity_requests':['worker_id uuid','status text','representative_site_id uuid','quantity numeric','unit_price_yen numeric','version integer'],
  'private.route_billing_quantity_evidence':['site_id uuid','customer_id uuid'],
 };
 for(const [table,columns]of Object.entries(fields))for(const column of columns)await db.exec(`alter table ${table} add column if not exists ${column}`);
 const old=await fs.readFile('supabase/migrations/20261012053842_route_customer_billing_connection.sql','utf8');
 const signed=await fs.readFile('supabase/migrations/20261013181708_route_signed_checkout_customer_billing.sql','utf8');
 const extract=(source,startMarker,endMarker)=>{
  const start=source.indexOf(startMarker),end=source.indexOf(endMarker,start);
  if(start<0||end<start||source.indexOf(startMarker,start+1)!==-1)throw Error('route reader source anchor changed');
  return source.slice(start,source.indexOf(';',end)+1);
 };
 await db.exec(extract(old,'create function private.route_billing_site_daily_rate(','revoke all on function private.route_billing_site_daily_rate('));
 await db.exec(extract(signed,'create or replace function private.route_signed_site_rates(','revoke all on function private.route_signed_site_rates('));
 await db.exec(await fs.readFile('docs/review/invoice-month-close/route_components.production.sql.review-only','utf8'));
 await db.exec(await fs.readFile('docs/review/invoice-month-close/route_helpers.production.sql.review-only','utf8'));
 const start=signed.indexOf('CREATE OR REPLACE FUNCTION private.route_billing_invoice_components('),end=signed.indexOf('$function$;',signed.indexOf('AS $function$',start));
 if(start<0||end<start)throw Error('route invoice reader source anchor changed');
 await db.exec(signed.slice(start,end+'$function$;'.length));
 for(const [signature,expected]of [
  ['route_signed_checkout_sources(uuid,date,date)','657a3e0a3511f600e440e23026d8a73d'],
  ['route_signed_checkout_components(uuid,uuid,date,date)','55ec3b7eaaf288986bea1c32c3e0be50'],
  ['route_billing_invoice_blocked(uuid,uuid,date,date)','2601bbc4fe21fa0a609c52686e315ee7'],
 ])check(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',['private.'+signature]),expected);
 for(const signature of ['route_signed_checkout_sources(uuid,date,date)','route_signed_checkout_components(uuid,uuid,date,date)','route_billing_invoice_blocked(uuid,uuid,date,date)','route_billing_invoice_components(uuid,uuid,date,date)'])await db.exec(`revoke all on function private.${signature} from public,anon,authenticated`);
 for(const role of ['anon','authenticated'])for(const signature of ['route_signed_site_rates(uuid,uuid,text)','route_billing_site_daily_rate(uuid,uuid)','route_billing_invoice_components(uuid,uuid,date,date)'])check(await q("select has_function_privilege($1,$2,'EXECUTE') v",[role,'private.'+signature]),false);
 const customer=await q('select customer_id v from public.invoices where id=$1',[pending.parent]);
 const route=id(53000),report=id(53001),clockIn=id(53002),clockOut=id(53003),site1=id(53004),site2=id(53005),stop1=id(53006),stop2=id(53007);
 const insertRows=async()=>{
  await db.query("insert into public.sites(id,company_id,customer_id,name) values($1,$3,$4,'合成ルートA'),($2,$3,$4,'合成ルートB')",[site1,site2,A,customer]);
  await db.query('insert into public.site_financial_settings(company_id,site_id,billing_unit_price_yen) values($1,$2,20000),($1,$3,20000)',[A,site1,site2]);
  await db.query("insert into public.daily_reports(id,company_id,report_date,status,signed_at,representative_signature_json,supervisor_signature_json,signature_json,route_assignment_id) values($1,$2,'2020-10-21','signed','2020-10-21T18:00:00Z','[1]','[2]','[2]',$3)",[report,A,route]);
  await db.query('insert into public.daily_report_workers values($1,$2)',[report,UA]);
  await db.query("insert into public.attendance_entries(company_id,worker_id,work_date,source_report_id,route_assignment_id) values($1,$2,'2020-10-21',$3,$4)",[A,UA,report,route]);
  await db.query("insert into public.attendance_verifications(id,company_id,worker_id,work_date,event_type,route_assignment_id,confirmed_at,daily_report_id,source_clock_in_id) values($1,$3,$4,'2020-10-21','clock_in',$5,'2020-10-21T08:00:00Z',$6,null),($2,$3,$4,'2020-10-21','clock_out',$5,'2020-10-21T17:00:00Z',$6,$1)",[clockIn,clockOut,A,UA,route,report]);
  await db.query('insert into public.route_stops(company_id,id,route_assignment_id,site_id) values($1,$2,$4,$5),($1,$3,$4,$6)',[A,stop1,stop2,route,site1,site2]);
  for(const [n,stop,hour]of [[53010,stop1,9],[53012,stop2,13]]){
   for(const [capture,kind,time]of [[id(n),'start',hour],[id(n+1),'end',hour+2]]){
    await db.query("insert into private.route_journey_captures(id,company_id,source_clock_in_id,route_assignment_id,work_date,worker_id,route_stop_id,recorded_at) values($1,$2,$3,$4,'2020-10-21',$5,$6,$7)",[capture,A,clockIn,route,UA,stop,`2020-10-21T${String(time).padStart(2,'0')}:00:00Z`]);
    await db.query('insert into private.route_journey_visit_events(capture_id,source_clock_in_id,kind,start_capture_id,route_stop_id) values($1,$2,$3,$4,$5)',[capture,clockIn,kind,id(n),stop]);
   }
  }
 };
 const component=(company=A,party=customer)=>q("select private.route_billing_invoice_components($1,$2,'2020-10-01','2020-10-31') v",[company,party]);
 await db.exec('begin');
 try{
  await insertRows();
  const actual=await component();check(actual.blocked,false);check(actual.subtotal,20000);check(actual.tax,2000);check(actual.sites.length,1);check(actual.sites[0].lines[0].quantity,1);check(actual.sites[0].visited_site_ids,[site1,site2]);
  check((await component(B)).subtotal,0);check((await component(A,id(53999))).subtotal,0);
  check((await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent])).grand_total,132000);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'data_changed');
  await db.exec('savepoint missing_exit');
  await db.query('delete from private.route_journey_visit_events where capture_id=$1',[id(53013)]);
  check((await component()).blocked,true);check(await q('select invoice_month_close_candidate.precheck($1) v',[pending.parent]),'route_unverified');
  await db.exec('rollback to savepoint missing_exit;release savepoint missing_exit');
  await db.query('update public.site_financial_settings set billing_unit_price_yen=21000 where site_id=$1',[site2]);
  check((await component()).blocked,true);
 }finally{await db.exec('rollback');}
 check((await component()).subtotal,0);
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 return async()=>{
  const before=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  await insertRows();
  const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  check(proposal.grand_total,Number(before.grand_total)+22000);
  await db.query('update public.invoices set snapshot=$1::jsonb,subtotal=$2,tax=$3,welfare_amount=$4,grand_total=$5,updated_at=clock_timestamp() where id=$6',[JSON.stringify(proposal.proposed_snapshot),proposal.subtotal,proposal.tax,proposal.welfare,proposal.grand_total,pending.parent]);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 };
}
