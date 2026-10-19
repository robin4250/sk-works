import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const runtime=await import(pathToFileURL(process.argv[2]).href);
const realDatabase=process.env.SKO_ATOMIC_LEDGER_DATABASE_URL;
let pg;
if(realDatabase){
 const target=new URL(realDatabase);
 assert.ok(['127.0.0.1','localhost'].includes(target.hostname)&&target.pathname==='/sko_route_atomic_ledger_fixture','Only disposable local ledger fixture permitted');
 const Client=runtime.Client??runtime.default?.Client;pg=new Client({connectionString:realDatabase});await pg.connect();
 assert.match((await pg.query('show server_version')).rows[0].server_version,/^17\./);
}
const db=realDatabase?{exec:sql=>pg.query(sql),query:(sql,args)=>pg.query(sql,args),close:()=>pg.end()}:new runtime.PGlite();
const root=new URL('../',import.meta.url);
const read=p=>fs.readFile(new URL(p,root),'utf8');
try {
 for(const p of ['tool/fixtures/route_journey_capture/schema.sql','supabase/migrations/20261008204012_route_journey_capture_staged.sql','supabase/migrations/20261010132957_route_journey_visit_lifecycle.sql','supabase/migrations/20261010222139_route_manual_visit_capture.sql','supabase/migrations/20261012010000_route_final_visit_clock_out.sql']) await db.exec(await read(p));
 await db.exec(`alter table attendance_verifications add column confirmed_at timestamptz,add column attempted_at timestamptz;
 alter table daily_reports add column signed_at timestamptz,add column signature_json jsonb;
 alter table sites add column company_id uuid,add column customer_id uuid,add column formal_name text;
 create table attendance_entries(id uuid,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,source_report_id uuid,work_date date,base_man_days numeric,work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[]);`);
 const original=await read('supabase/migrations/20261013181708_route_signed_checkout_customer_billing.sql');
 const begin=original.indexOf('create or replace function private.route_signed_checkout_sources(');
 const end=original.indexOf('create or replace function private.route_signed_site_rates(',begin);
 await db.exec(original.slice(begin,end));
 const candidate=await read('docs/candidates/route_checkout_atomic_ledger_20261020.sql.review-only');
 await db.exec(`create role service_role bypassrls;create role unexpected_receipt_grantee;grant usage on schema private to service_role;alter default privileges in schema private grant all on tables to service_role;alter default privileges in schema private grant execute on functions to service_role;alter default privileges in schema private grant insert on tables to unexpected_receipt_grantee`);
 await assert.rejects(db.exec(candidate),/Unexpected non-owner ACL.*route_checkout_atomic_finishes/);await db.exec('rollback');
 assert.equal((await db.query("select to_regclass('private.route_checkout_atomic_finishes') t")).rows[0].t,null);
 await db.exec('alter default privileges in schema private revoke insert on tables from unexpected_receipt_grantee;alter default privileges in schema private grant execute on functions to unexpected_receipt_grantee');
 await assert.rejects(db.exec(candidate),/Unexpected non-owner ACL.*reject_atomic_finish_receipt_change/);await db.exec('rollback');
 assert.equal((await db.query("select to_regclass('private.route_checkout_atomic_finishes') t")).rows[0].t,null);
 await db.exec('alter default privileges in schema private revoke execute on functions from unexpected_receipt_grantee');
 await db.exec('alter function private.route_signed_checkout_sources(uuid,date,date) volatile');
 await assert.rejects(db.exec(candidate),/security metadata drift/);await db.exec('rollback');
 await db.exec('alter function private.route_signed_checkout_sources(uuid,date,date) stable;grant execute on function private.route_signed_checkout_sources(uuid,date,date) to service_role');
 await assert.rejects(db.exec(candidate),/security metadata drift/);await db.exec('rollback');
 await db.exec('revoke execute on function private.route_signed_checkout_sources(uuid,date,date) from service_role');
 await db.exec(candidate);
 assert.equal((await db.query("select rolbypassrls from pg_roles where rolname='service_role'")).rows[0].rolbypassrls,true);
 assert.equal((await db.query("select has_table_privilege('service_role','private.route_checkout_atomic_finishes','insert') allowed")).rows[0].allowed,false);
 await db.exec('set role service_role');
 await assert.rejects(db.exec("insert into private.route_checkout_atomic_finishes(checkout_id) values('90000000-0000-0000-0000-000000000001')"),/permission denied for table/);
 await db.exec('reset role');
 console.log('PASS unknown table/function default grants fail closed; service_role BYPASSRLS cannot directly INSERT despite seeded default grants');
 const id=n=>`50000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [company,actor,worker,route,stop,site,customer]=[1,2,3,4,5,6,7].map(id);
 await db.query("select set_config('test.uid',$1,false)",[actor]);
 await db.query('insert into companies values($1)',[company]);
 await db.query("insert into company_members values($1,$2,'member')",[company,actor]);
 await db.query("insert into workers values($1,$2,$3,'fixture worker','active')",[worker,company,actor]);
 await db.query('insert into route_assignments values($1,$2)',[route,company]);
 await db.query("insert into sites values($1,'fixture site',$2,$3,null)",[site,company,customer]);
 await db.query("insert into route_stops values($1,$2,$3,1,null,'fixture site')",[stop,route,site]);
 await db.query('insert into private.route_journey_rollouts values($1,true)',[company]);
 await db.exec('grant insert on attendance_verifications to authenticated');
 const payload=attempt=>({capture_contract_version:1,gps_capture_status:'missing',photo_capture_status:'missing',gps_captured_at:null,photo_captured_at:null,photo_observed_at:null,captured_address:null,latitude:null,longitude:null,accuracy_m:null,photo_storage_path:null,attempted_at:attempt});
 async function seed(n){
  const source=id(n),report=id(n+1),arrival=id(n+2),checkout=id(n+3);
  await db.query("insert into daily_reports(id,company_id,site_id,route_assignment_id,report_date,updated_by,status,signed_at,signature_json) values($1,$2,null,$3,'2026-10-13',$4,'signed',clock_timestamp(),'[[1,1]]')",[report,company,route,actor]);
  await db.query("insert into attendance_verifications values($1,$2,$3,null,$4,'2026-10-13','clock_in',null,$5,'manual',null,clock_timestamp()-interval '1 hour',clock_timestamp()-interval '1 hour')",[source,company,worker,route,report]);
  await db.query('insert into daily_report_workers values($1,$2)',[report,worker]);
  await db.query("insert into attendance_entries values($1,$2,$3,null,$4,$5,'2026-10-13',1,'day',0,0,'{}')",[id(n+4),company,worker,route,report]);
  await db.exec('set role authenticated');
  const started=(await db.query('select public.save_route_journey_visit($1,$2,$3,$4,$5,$6,$1) v',[arrival,source,stop,'direct',payload('2026-10-13T00:00Z'),'start'])).rows[0].v;
  return {source,report,arrival,checkout,started};
 }
 async function close(s,claimed){return db.query("insert into attendance_verifications values($1,$2,$3,null,$4,'2026-10-13','clock_out',$5,$6,'manual',null,coalesce($7::timestamptz,clock_timestamp()),coalesce($7::timestamptz,clock_timestamp()))",[s.checkout,company,worker,route,s.source,s.report,claimed]);}
 async function ready(s){await db.exec('reset role');return (await db.query("select source_ready from private.route_signed_checkout_sources($1,'2026-10-13','2026-10-13') where source_clock_in_id=$2",[company,s.source])).rows[0].source_ready;}
 // Reproduce the known preseeded ID/attempt attack. No receipt is created.
 let s=await seed(20);
 await db.query('select public.save_route_journey_visit($1,$2,$3,$4,$5,$6,$7)',[s.checkout,s.source,stop,'direct',payload(s.started.recorded_at),'end',s.arrival]);
 await close(s,s.started.recorded_at);
 assert.equal(await ready(s),false,'Preseeded end must not gain atomic eligibility');
 assert.equal((await db.query('select count(*)::int n from private.route_checkout_atomic_finishes')).rows[0].n,0);
 console.log('PASS preseeded ID/attempt counterexample rejected without server receipt');
 // Trigger-generated legitimate final end creates exactly one receipt.
 s=await seed(40);await close(s,null);assert.equal(await ready(s),true);
 let receipt=(await db.query('select * from private.route_checkout_atomic_finishes where checkout_id=$1',[s.checkout])).rows[0];
 assert.equal(receipt.source_clock_in_id,s.source);assert.equal(receipt.end_capture_id,s.checkout);assert.equal(receipt.start_capture_id,s.arrival);
 await db.exec('set role authenticated');await assert.rejects(close(s,null),/duplicate/);
 await assert.rejects(db.query('insert into private.route_checkout_atomic_finishes select * from private.route_checkout_atomic_finishes'),/permission denied/);
 await assert.rejects(db.query('update private.route_checkout_atomic_finishes set attempted_at=attempted_at'),/permission denied/);
 await assert.rejects(db.query('delete from private.route_checkout_atomic_finishes'),/permission denied/);
 await db.exec('reset role');
 await assert.rejects(db.query('update private.route_checkout_atomic_finishes set attempted_at=attempted_at'),/append-only/);
 await assert.rejects(db.query('delete from private.route_checkout_atomic_finishes'),/append-only/);
 assert.equal((await db.query('select count(*)::int n from private.route_checkout_atomic_finishes')).rows[0].n,1);
 console.log('PASS genuine trigger receipt, duplicate retry, direct client writes and ledger mutation denial');
 // A failure later in the checkout INSERT rolls the receipt and capture back too.
 s=await seed(60);await db.exec('reset role');
 await db.exec(`create function private.fixture_fail_checkout() returns trigger language plpgsql as $$begin if new.event_type='clock_out' then raise exception 'fixture late insert failure';end if;return new;end$$;create trigger zz_fixture_fail_checkout before insert on attendance_verifications for each row execute function private.fixture_fail_checkout()`);
 await db.exec('set role authenticated');await assert.rejects(close(s,null),/fixture late insert failure/);await db.exec('reset role');
 assert.equal((await db.query('select count(*)::int n from private.route_checkout_atomic_finishes where checkout_id=$1',[s.checkout])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from private.route_journey_captures where id=$1',[s.checkout])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from attendance_verifications where id=$1',[s.checkout])).rows[0].n,0);
 await db.exec('drop trigger zz_fixture_fail_checkout on attendance_verifications;set role authenticated');await close(s,null);assert.equal(await ready(s),true);
 console.log('PASS late checkout failure rolls receipt/capture/event back; retry creates one legitimate pair');
} catch(error) {console.error(error.message,error.where??'');process.exitCode=1;} finally {await db.close();}
