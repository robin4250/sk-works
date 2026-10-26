process.on("uncaughtException",e=>{console.error(JSON.stringify({error:e.message,where:e.where,detail:e.detail}));process.exit(1)});
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {pathToFileURL} from 'node:url';import {execFileSync}from'node:child_process';
const here=path.dirname(new URL(import.meta.url).pathname);const base=process.argv[4]||path.resolve(here,'../../doc-adjustment-buttons-candidate');const fixture=process.argv[3]||path.resolve(here,'../../sk-works-source');
const {PGlite}=await import(pathToFileURL(process.argv[2]||path.resolve(here,'../../apple-enrollment-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js')));
const {setupExpenseCostFixture}=await import(pathToFileURL(fixture+'/tool/fixtures/expense_cost_fixture.mjs'));
process.chdir(fixture);const db=new PGlite();await setupExpenseCostFixture(db);
for(const n of ['expense_settlement_choice_cost_extension.sql','expense_cost_amounts.sql'])await db.exec(fs.readFileSync(fixture+'/supabase/tests/'+n,'utf8'));
await db.exec(`alter table invoices add column if not exists approval_finalized_at timestamptz;alter table payment_certificates add column if not exists finalized_at timestamptz;create table if not exists invoice_approvals(invoice_id uuid,status text);create function private.require_reauthentication_session()returns uuid language sql as $$select auth.uid()$$;create function private.expense_cost_direction_v2_enabled(uuid)returns boolean language sql as $$select false$$;`);
for(const n of ['private.refresh_automatic_invoice.sql','private.refresh_automatic_payment_certificate.sql','private.certificate_calculation_rows.sql','private.expense_payment_v2_envelope.sql','private.expense_payment_v2_guard.sql'])await db.exec(fs.readFileSync(base+'/supabase/tests/fixtures/trade_document_adjustments_20261026/'+n,'utf8'));
// Fixture-only neutral tables needed by the unchanged row/catalog guard, no real data.
for(const t of ['invoice_detail_lines','daily_reports','daily_report_workers','payroll_statements'])await db.exec(`create table if not exists public.${t}(id integer primary key,note text)`);
await db.exec(`create trigger actual_v2_guard before insert or update or delete on payment_certificates for each row execute function private.expense_payment_v2_guard();`);
if(process.env.SKO_FIXTURE_PRODUCTION_DEFAULT_ACL==='1')await db.exec('alter default privileges in schema public grant execute on functions to anon,authenticated,service_role');
execFileSync('python3',[here+'/prepare_compact.py']);
const snapshot=(await db.query(fs.readFileSync(here+'/capture-compact.sql','utf8'))).rows[0].snapshot;
fs.writeFileSync(here+'/fixture-before.json',JSON.stringify(snapshot));
execFileSync('python3',['-c',`import sys,json;sys.path.insert(0,sys.argv[1]);import prepare_compact as prepare;s=json.load(open(sys.argv[1]+'/fixture-before.json'));a,b=prepare.compose(s,open(sys.argv[2]).read());open(sys.argv[1]+'/fixture-install.sql','w').write(a);open(sys.argv[1]+'/fixture-restore.sql','w').write(b)`,here,base+'/supabase/review/document_adjustment_install.incomplete.sql']);
const install=fs.readFileSync(here+'/fixture-install.sql','utf8'),restore=fs.readFileSync(here+'/fixture-restore.sql','utf8');let checks=0;
async function rejects(sql,re){try{await assert.rejects(db.exec(sql),re)}catch(e){e.message+=' at check '+checks+' expected '+re;throw e}await db.exec('rollback');checks++;}
await db.exec(install);checks++;
assert.equal((await db.query('select count(*)::int n from document_adjustment_private.rollout')).rows[0].n,0);checks++;
await rejects(install,/schema_exists/);
await db.exec(restore);checks++;
assert.equal((await db.query("select to_regnamespace('document_adjustment_private')is null ok")).rows[0].ok,true);checks++;
await db.exec(install);checks++;
await db.exec('create view public.unknown_adjustment_dependency as select * from document_adjustment_private.audit');
await rejects(restore,/depend|unknown/);assert.equal((await db.query("select to_regnamespace('document_adjustment_private')is not null ok")).rows[0].ok,true);checks++;
await db.exec('drop view public.unknown_adjustment_dependency');
await db.exec(restore);checks++;
// Dependency metadata drift is refused before installation, atomically.
await db.exec("alter function private.expense_payment_v2_guard()set statement_timeout='12s'");await rejects(install,/metadata_drift/);assert.equal((await db.query("select to_regnamespace('document_adjustment_private')is null ok")).rows[0].ok,true);checks++;
await db.exec('alter function private.expense_payment_v2_guard()reset statement_timeout');
await db.exec(install);checks++;
await db.exec("create function public.external_runtime_adjustment_dependency()returns void language plpgsql as $$begin perform 1 from document_adjustment_private.audit;end$$");
await rejects(restore,/external_runtime_dependency/);await db.exec('drop function public.external_runtime_adjustment_dependency()');
await db.exec('create index fixture_external_new_index on public.invoices(status)');await rejects(restore,/catalogue_changed/);await db.exec('drop index fixture_external_new_index');
await db.exec("grant execute on function document_adjustment_private.guard_catalogue()to service_role");await rejects(restore,/catalogue_changed/);await db.exec("revoke execute on function document_adjustment_private.guard_catalogue()from service_role");
await db.exec(restore);checks++;
await db.exec("insert into public.daily_reports values(1,'protected')");
const malicious=install.replace('do $rows$ declare r record',"update public.daily_reports set note='changed';do $rows$ declare r record");
await rejects(malicious,/business_rows_changed/);assert.equal((await db.query("select note from daily_reports where id=1")).rows[0].note,'protected');checks++;
assert.equal((await db.query("select to_regnamespace('document_adjustment_private')is null ok")).rows[0].ok,true);checks++;
const badAcl=install.replace('do $access$ begin','grant execute on function public.read_trade_document_adjustments(uuid,text,date,uuid)to service_role;do $access$ begin');
await rejects(badAcl,/new_function_acl/);assert.equal((await db.query("select to_regnamespace('document_adjustment_private')is null ok")).rows[0].ok,true);checks++;
await db.exec(install);checks++;
// Even an audit sequence increment without surviving rows permanently refuses unused restore.
await db.exec("select nextval('document_adjustment_private.audit_id_seq')");await rejects(restore,/catalogue_changed/);
await db.close();console.log(JSON.stringify({checks,production_applied:false,fixture:'PGlite isolated metadata/restoration only'}));
