// Read-only audit against disposable PostgreSQL, never production.
// node tool/audit_payment_certificate_math.mjs /tmp/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const c='00000000-0000-0000-0000-000000000001',p='00000000-0000-0000-0000-000000000002',w='00000000-0000-0000-0000-000000000003',u='00000000-0000-0000-0000-000000000004';
try {
await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.company_members(company_id uuid,user_id uuid,role text);
select set_config('test.uid','${u}',false);insert into public.company_members values('${c}','${u}','admin');
create table public.workers(id uuid,company_id uuid,partner_company_id uuid);
insert into public.workers values('${w}','${c}','${p}');
create table public.partner_companies(id uuid,company_id uuid,name text);
insert into public.partner_companies values('${p}','${c}','Test company');
create table public.sites(id uuid,company_id uuid,name text,formal_name text);
create table public.attendance_entries(company_id uuid,worker_id uuid,site_id uuid,work_date date,base_man_days numeric,overtime_hours numeric,early_hours numeric,work_category text,allowance_names text[]);
create table public.partner_payment_settings(company_id uuid,partner_company_id uuid,daily_rate_yen integer,overtime_hour_rate_yen integer,early_hour_rate_yen integer,night_hour_rate_yen integer,night_day_rate_yen integer,night_overtime_hour_rate_yen integer,holiday_day_rate_yen integer,holiday_overtime_hour_rate_yen integer,holiday_night_day_rate_yen integer,holiday_night_overtime_hour_rate_yen integer,rate_formula jsonb,allowances jsonb,welfare_rate numeric,tax_rate numeric);
insert into public.partner_payment_settings values('${c}','${p}',0,0,0,0,0,0,0,0,0,0,'{"base_mode":"hourly","hourly_rate_yen":1500,"hours_per_day":8}','[]',0,0);
create table public.payment_certificates(id uuid default gen_random_uuid(),company_id uuid,partner_company_id uuid,period_start date,period_end date,status text,gross_amount integer,deductions integer,net_amount integer,snapshot jsonb,automatic_calculation boolean,calculation_blocked boolean,revision integer default 1,updated_at timestamptz);
insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,2,0,'day','{}');`);
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261006180455_fix_rate_formula_combined_multipliers.sql'),'utf8'));
const sql=fs.readFileSync(path.join(root,'supabase/migrations/20261006181320_finalize_shared_rate_formula_semantics.sql'),'utf8');
await db.exec(sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate')));
const refresh=()=>db.exec(`select private.refresh_automatic_payment_certificate('${c}','${p}','2026-10-01')`);
const amounts=async()=>{const certificate=(await db.query('select id,gross_amount,net_amount from public.payment_certificates')).rows[0];const lines=(await db.query(`select * from public.payment_certificate_detail_rows('${certificate.id}')`)).rows;return {...certificate,detail_total:lines.reduce((s,l)=>s+l.amount_yen,0),lines};};
await refresh();
try {await amounts();throw Error('Expected ambiguity not reproduced');} catch(error) {if(error.code!=='42702')throw error;console.log(JSON.stringify({case:'default_plpgsql_variable_conflict',sqlstate:error.code,message:error.message}));}
// Conditional arithmetic audit: workaround is session-local and never a fix.
await db.exec("set plpgsql.variable_conflict='use_column'");
await db.exec(sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.payment_certificate_detail_rows')));
const hourly=await amounts();assert.equal(hourly.gross_amount,3750);assert.equal(hourly.detail_total,3750);console.log(JSON.stringify({case:'hourly1500_normal8h_overtime2h',expected:15750,actual:hourly}));
await db.exec(`delete from public.payment_certificates;delete from public.attendance_entries;update public.partner_payment_settings set daily_rate_yen=10001,rate_formula='{}';insert into public.sites values('00000000-0000-0000-0000-000000000005','${c}','Site A',''),('00000000-0000-0000-0000-000000000006','${c}','Site B','');insert into public.attendance_entries select '${c}','${w}',id,'2026-10-01',0.5,0,0,'day','{}' from public.sites;`);
await refresh();const fractions=await amounts();assert.equal(fractions.gross_amount,10001);assert.equal(fractions.detail_total,10002);console.log(JSON.stringify({case:'two_sites_half_day_10001',actual:fractions}));
await db.exec(`delete from public.payment_certificates;delete from public.attendance_entries;update public.partner_payment_settings set daily_rate_yen=12000;insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,0,0,'day','{}');`);
await refresh();await db.exec(`update public.payment_certificates set status='finalized';update public.partner_payment_settings set daily_rate_yen=13000;`);await refresh();const finalized=await amounts();assert.equal(finalized.gross_amount,12000);assert.equal(finalized.detail_total,13000);console.log(JSON.stringify({case:'finalized_then_rate_change',actual:finalized}));
console.log('Historical defect reproductions completed. Applying forward fix only to disposable PostgreSQL.');
await db.exec("set plpgsql.variable_conflict='error'");
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261008035432_certificate_canonical_snapshot_math.sql'),'utf8'));
const reset=async(rate,formula,rows)=>{await db.exec(`delete from public.payment_certificates;delete from public.attendance_entries;update public.partner_payment_settings set daily_rate_yen=${rate},rate_formula='${formula}';${rows}`);};
await reset(0,'{"base_mode":"hourly","hourly_rate_yen":1500,"hours_per_day":8}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,2,0,'day','{}');`);
await refresh();const fixedHourly=await amounts();assert.equal(fixedHourly.gross_amount,15750);assert.equal(fixedHourly.detail_total,15750);console.log(JSON.stringify({case:'fixed_hourly',actual:fixedHourly}));
await reset(10001,'{}',`insert into public.attendance_entries select '${c}','${w}',id,'2026-10-01',0.5,0,0,'day','{}' from public.sites;`);
await refresh();const fixedFraction=await amounts();assert.equal(fixedFraction.gross_amount,10002);assert.equal(fixedFraction.detail_total,10002);assert.ok(fixedFraction.lines.every(l=>l.quantity_label==='0.5人'));
await db.exec(`update public.payment_certificates set status='finalized';update public.partner_payment_settings set daily_rate_yen=20000;`);await refresh();const frozen=await amounts();assert.equal(frozen.gross_amount,10002);assert.equal(frozen.detail_total,10002);
await db.exec("update public.payment_certificates set snapshot='{}'");const legacy=await amounts();assert.equal(legacy.detail_total,10002);assert.equal(legacy.lines.length,1);assert.equal(legacy.lines[0].quantity_label,'');
for (const [category,expected] of [['day',20536],['night',30522],['holiday',27524],['holiday_night',32517]]) {
 await reset(12000,'{}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,2,1,'${category}',array['手当']);`);
 await db.exec(`update public.partner_payment_settings set allowances='[{"name":"手当","amount_yen":500}]',welfare_rate=3,tax_rate=10;`);
 await refresh();const actual=await amounts();assert.equal(actual.gross_amount,expected);assert.equal(actual.detail_total,expected);
}
await db.exec("update public.partner_payment_settings set allowances='[]',welfare_rate=0,tax_rate=0;");
for (const [category,base,early] of [['day',12000,1650],['night',18000,2475],['holiday',16200,2228],['holiday_night',19200,2640]]) {
 await reset(12000,'{"early_multiplier":1.1,"overtime_multiplier":1.25}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,0,1,'${category}','{}');`);
 await refresh();const actual=await amounts();assert.equal(actual.gross_amount,base+early);assert.equal(actual.lines.find(l=>l.work_content==='早出').unit_price_yen,early);
}
await db.exec('update public.partner_payment_settings set early_hour_rate_yen=2100;');
for (const [category,base] of [['day',12000],['night',18000],['holiday',16200],['holiday_night',19200]]) {
 await reset(12000,'{"early_multiplier":1.1}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,0,1,'${category}','{}');`);await refresh();assert.equal((await amounts()).gross_amount,base+2100);
}
await db.exec('update public.partner_payment_settings set early_hour_rate_yen=0;');
await db.exec(`update public.partner_payment_settings set overtime_hour_rate_yen=2200,allowances='[]',welfare_rate=0,tax_rate=0;`);
await reset(12000,'{"overtime_multiplier":1.7}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,2,0,'day','{}');`);
await refresh();assert.equal((await amounts()).gross_amount,16400);
// Approved paid leave is a separate source, and rest corrections remove attendance:
// absence of billable attendance creates no persisted certificate.
await db.exec('delete from public.attendance_entries');await refresh();assert.equal((await db.query('select count(*)::integer n from public.payment_certificates')).rows[0].n,0);
// Restore historical fixture for authorization guard probes.
await reset(12000,'{}',`insert into public.attendance_entries values('${c}','${w}',null,'2026-10-01',1,0,0,'day','{}');`);await refresh();
const id=(await amounts()).id;
await db.exec("select set_config('test.uid','',false)");try{await db.query(`select * from public.payment_certificate_detail_rows('${id}')`);assert.fail('anonymous allowed');}catch(e){assert.match(e.message,/authentication required/);}
await db.exec("select set_config('test.uid','00000000-0000-0000-0000-000000000099',false)");try{await db.query(`select * from public.payment_certificate_detail_rows('${id}')`);assert.fail('other company allowed');}catch(e){assert.match(e.message,/permission required/);}
const acl=(await db.query("select has_function_privilege('anon','public.payment_certificate_detail_rows(uuid)','execute') as anon_public,has_function_privilege('authenticated','private.certificate_calculation_rows(uuid,uuid,date,date)','execute') as auth_private,has_function_privilege('authenticated','public.payment_certificate_detail_rows(uuid)','execute') as auth_public")).rows[0];assert.deepEqual(acl,{anon_public:false,auth_private:false,auth_public:true});
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261008035432_certificate_canonical_snapshot_math.sql'),'utf8'));
if(process.argv.includes('--seal-snapshots')) {
 await db.exec(`create table companies(id uuid primary key,name text,company_seal_enabled boolean default true,updated_at timestamptz);
 insert into companies(id,name) values('${c}','株式会社テスト建設');
 create function private.account_access_allowed() returns boolean language sql as $$select true$$;
 create table invoices(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payroll_statements(id uuid primary key,company_id uuid,detail jsonb);
 create function private.refresh_automatic_invoice(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.invoices; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb language sql as $$
 select jsonb_build_object('company_seal_enabled',c.company_seal_enabled,'old',true)
 from payroll_statements ps join companies c on c.id=ps.company_id where ps.id=p_statement_id $$;
 create function private.saved_site_payment_document(p_proposal uuid,p_company uuid) returns jsonb language plpgsql as $$
 declare result jsonb;
 begin select jsonb_build_object('snapshot_version',2,'parent_company_seal_enabled',parent.company_seal_enabled)
 into result from companies parent where parent.id=p_company;return result;end $$;`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261009011357_company_seal_aoyagi_style.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261009012730_company_seal_document_snapshots.sql'),'utf8'));
 await db.exec("update companies set company_seal_style='aoyagi_reisho'");
 const legacyBefore=(await db.query('select snapshot from payment_certificates')).rows[0].snapshot;
 await refresh();
 assert.equal((await db.query("select snapshot ? 'company_seal_snapshot' present from payment_certificates")).rows[0].present,false);
 assert.deepEqual((await db.query('select snapshot from payment_certificates')).rows[0].snapshot,legacyBefore);
 await db.exec('delete from payment_certificates');await refresh();
 const initial=(await db.query('select snapshot,updated_at,revision from payment_certificates')).rows[0];
 assert.equal(initial.snapshot.company_seal_snapshot.style,'aoyagi_reisho');
 await db.exec("update companies set name='株式会社別名',company_seal_style='legacy'");
 await refresh();
 const repeated=(await db.query('select snapshot,updated_at,revision from payment_certificates')).rows[0];
 assert.deepEqual(repeated.snapshot,initial.snapshot);
 assert.equal(repeated.revision,initial.revision);
 assert.equal(String(repeated.updated_at),String(initial.updated_at));
 await db.exec('update attendance_entries set overtime_hours=3');await refresh();
 const changed=(await db.query('select snapshot,revision from payment_certificates')).rows[0];
 assert.deepEqual(changed.snapshot.company_seal_snapshot,initial.snapshot.company_seal_snapshot);
 assert.equal(changed.revision,initial.revision+1);
 console.log('PASS: real payment cron stable revision, old draft not backfilled, financial changes retain original seal');
}
console.log('Forward fix passed: hourly, fractional rows, frozen snapshot, legacy amount, anonymous/company guards, ACLs, configured category combinations, explicit overrides, no attendance and repeated migration.');
} finally {await db.close();}
