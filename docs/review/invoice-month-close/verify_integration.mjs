import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(process.env.SKO_ADJUSTMENT_ROOT);
let wrapper=await readFile(resolve(process.env.SKO_PREVIEW_WRAPPER),'utf8');
const checkSql=await readFile(process.env.SKO_MONTH_CLOSE_SQL,'utf8');
const guardedSql=await readFile(process.env.SKO_GUARDED_SQL,'utf8');
const declarations=`const closeSql=${JSON.stringify(checkSql)};const guardedSql=${JSON.stringify(guardedSql)};\n`;
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
const readiness=async()=>(await db.query('select invoice_month_close_candidate.guarded($1) v',[frozen.id])).rows[0].v;
assert.equal(await readiness(),'ready');
await addExtras();assert.equal(await readiness(),'data_changed');
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2020-10-25','2020-10-27')",[company,site]);
await db.query("update daily_reports set status='draft' where id=$1",[id(900)]);assert.equal(await readiness(),'report_pending');
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
console.log(JSON.stringify({real_refresh_preview_gate_readiness:true,matching_snapshot_ready:true,late_extra_work_rejected:true,old_report_pending_rejected:true,original_invoice_unchanged:true,route_source_stub:true,approval_not_connected:true}));
`;
const marker='console.log(JSON.stringify({invoice_correction_preview:true';assert.equal(wrapper.split(marker).length,2);
wrapper=wrapper.replaceAll('2026-10-','2020-10-').replace("const original=await readFile(originalPath,'utf8');","const original=(await readFile(originalPath,'utf8')).replaceAll('2026-10-','2020-10-');").replace("const marker='let checks=0;'",()=>declarations+"const marker='let checks=0;'").replace(marker,()=>injection+marker);
const generated=resolve(root,'tool/verify_month_close_integration.generated.mjs');
try{await writeFile(generated,wrapper);const r=spawnSync(process.execPath,[generated,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(generated).catch(()=>{});}
