// Reuse the existing signed-checkout fixture and real invoice SQL; no production connection.
import fs from 'node:fs/promises';
const fixture = new URL('./verify_route_signed_checkout_billing.mjs', import.meta.url);
if (process.env.SKO_SIGNED_BILLING_DATABASE_URL) {
  throw new Error('This evidence regression uses disposable PGlite only.');
}
if (!process.argv[2]) throw new Error('Pass the disposable PGlite module path.');
let source = await fs.readFile(fixture, 'utf8');
const marker = "if (realDatabase) {\n  // Real Postgres connections serialize refreshing the same customer/month.";
if (source.split(marker).length !== 2) throw new Error('Existing fixture insertion point changed.');
const checks = `
// Preserve the original fixture so its existing finalization assertions still run.
await db.exec('begin');
const invoiceQuantity=async()=>Number((await db.query(\`select coalesce(sum((line->>'quantity')::numeric),0) quantity
 from invoices i cross join lateral jsonb_array_elements(i.snapshot->'sites') site
 cross join lateral jsonb_array_elements(site->'lines') line
 where line->>'quantity_contract'='one_per_worker_day_customer'\`)).rows[0].quantity);
const insertDay=async(day,seed,{complete=true}={})=>{
 const dayReport=id(seed),dayStart=id(seed+1),dayOut=id(seed+2),dayEntry=id(seed+3);
 await db.query(\`insert into attendance_verifications values($1,$2,$3,null,$4,$5,'clock_in',null,$6,$7),($8,$2,$3,null,$4,$5,'clock_out',$1,$6,$9)\`,
  [dayStart,company,worker,route,day,complete?dayReport:null,day+'T00:00Z',dayOut,day+'T09:00Z']);
 if(complete)await completeDay(day,seed);
};
const completeDay=async(day,seed)=>{
 const dayReport=id(seed),dayStart=id(seed+1),dayOut=id(seed+2),dayEntry=id(seed+3);
 await db.query(\`update attendance_verifications set daily_report_id=$1 where id in ($2,$3)\`,[dayReport,dayStart,dayOut]);
 await db.query(\`insert into daily_reports values($1,$2,null,$3,$4,'signed',$5,'[[1,1],[2,2]]')\`,[dayReport,company,route,day,day+'T09:00Z']);
 await db.query(\`insert into daily_report_workers values($1,$2)\`,[dayReport,worker]);
 for(let i=0;i<3;i++){
  const arrival=id(seed+10+i),end=id(seed+20+i),stop=id(30+i);
  await db.query(\`insert into private.route_journey_captures values($1,$2,$3,$4,$5,$6,$7,$8),($9,$2,$3,$4,$5,$6,$7,$10)\`,
   [arrival,company,dayStart,worker,route,stop,day,day+'T0'+(1+i*2)+':00Z',end,day+'T0'+(2+i*2)+':00Z']);
  await db.query(\`insert into private.route_journey_visit_events values($1,$2,$3,'start',$1),($4,$2,$3,'end',$1)\`,[arrival,dayStart,stop,end]);
 }
 // Existing attendance INSERT trigger is the final normal-source write.
 await db.query(\`insert into attendance_entries values($1,$2,$3,null,$4,$5,$6,1,'day',0,0,'{}')\`,[dayEntry,company,worker,route,dayReport,day]);
};
await insertDay('2026-10-13',100);
assert.equal(await invoiceQuantity(),2,'two signed workdays must bill two customer-days, not six visited sites');
await insertDay('2026-10-14',200,{complete:false});
await db.query(\`select public.refresh_signed_checkout_invoices($1)\`,[company]);
assert.equal(await invoiceQuantity(),2,'clock-only third day must not invent a report, signature or quantity');
assert.equal((await db.query('select count(distinct work_date)::int n from attendance_verifications')).rows[0].n,3);
assert.equal((await db.query('select count(*)::int n from attendance_entries')).rows[0].n,2);
await completeDay('2026-10-14',200);
assert.equal(await invoiceQuantity(),3,'normal complete evidence must refresh the draft to three automatically');
const three=(await db.query('select grand_total,snapshot from invoices')).rows[0];
assert.equal(three.grand_total,41492*3);
await db.query(\`select public.refresh_signed_checkout_invoices($1)\`,[company]);
assert.equal(await invoiceQuantity(),3,'refresh retry must not duplicate a man-day');
await db.exec('update site_financial_settings set billing_overtime_hour_rate_yen=5000');
await db.query(\`update attendance_entries set overtime_hours=1 where id=$1\`,[id(203)]);
assert.equal(await invoiceQuantity(),3,'editing an existing workday must not add another day');
assert.ok((await db.query('select grand_total from invoices')).rows[0].grand_total>three.grand_total,'registered overtime edit must update the draft amount');
await db.exec("update invoices set status='finalized',finalized_at=now()");
const frozenThree=(await db.query('select grand_total,snapshot from invoices')).rows[0];
await db.query(\`update attendance_entries set overtime_hours=0 where id=$1\`,[id(203)]);
await db.query(\`select public.refresh_signed_checkout_invoices($1)\`,[company]);
assert.deepEqual((await db.query('select grand_total,snapshot from invoices')).rows[0],frozenThree);
await db.exec('rollback');
console.log('PASS three-day evidence: two signed days plus clock-only day stays two; complete evidence becomes three; refresh/edit idempotent; finalized snapshot unchanged');
`;
source=source.replace(marker, checks+'\n'+marker);
source=source.replaceAll('import.meta.url', JSON.stringify(fixture.href));
try { await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64')); }
catch(error) { console.error(error.name+': '+error.message); process.exitCode=1; }
