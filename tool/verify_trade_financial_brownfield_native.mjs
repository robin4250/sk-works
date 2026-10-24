// Disposable PG17 only. No production destination, provider or credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';

const read = path => fs.readFile(path, 'utf8');
const manifest = JSON.parse(await read('tool/fixtures/trade_financial_brownfield/manifest.json'));
const blob = bytes => createHash('sha1').update(Buffer.from(`blob ${bytes.length}\0`)).update(bytes).digest('hex');
const md5 = text => createHash('md5').update(text).digest('hex');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const A = id(1), UA = id(11), B = id(2), PARTNER = id(23), CUSTOMER = id(90004);
let phase = 'fixture-destination', checks = 0, client;
const check = (actual, expected, label) => {assert.deepEqual(actual, expected, label); checks++;};
const reject = async (operation, pattern) => {await assert.rejects(operation, pattern); checks++;};

function routine(source, qualifiedName) {
  const escaped = qualifiedName.replaceAll('.', '\\.');
  const start = [...source.matchAll(new RegExp(`\\bcreate\\s+(?:or\\s+replace\\s+)?function\\s+${escaped}\\s*\\(`, 'ig'))];
  assert.equal(start.length, 1, `One source definition required: ${qualifiedName}`);
  const offset = start[0].index;
  const tail = source.slice(offset);
  const delimiter = /\bas\s+(\$[A-Za-z_0-9]*\$)/i.exec(tail);
  assert.ok(delimiter, `Source delimiter required: ${qualifiedName}`);
  const bodyStart = delimiter.index + delimiter[0].length;
  const bodyEnd = tail.indexOf(delimiter[1], bodyStart);
  assert.ok(bodyEnd >= bodyStart);
  const end = bodyEnd + delimiter[1].length;
  assert.equal(tail.slice(end).trimStart()[0], ';');
  return tail.slice(0, end) + ';';
}

function table(source, qualifiedName) {
  const escaped = qualifiedName.replaceAll('.', '\\.');
  const match = new RegExp(`create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?${escaped}\\s*\\([\\s\\S]*?\\n\\);`, 'i').exec(source);
  assert.ok(match, `Original table source required: ${qualifiedName}`);
  return match[0];
}

try {
  assert.equal(process.env.CI, 'true');
  assert.equal(process.platform, 'linux');
  assert.ok(!Object.keys(process.env).some(key => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(key)));
  const destination = new URL(process.env.SKO_CONSENT_FIXTURE_URL ?? '');
  assert.ok(['postgres:', 'postgresql:'].includes(destination.protocol));
  assert.ok(['127.0.0.1', 'localhost'].includes(destination.hostname));
  assert.equal(destination.username, 'postgres');
  assert.equal(destination.password, 'fixture-only');
  assert.equal(destination.pathname, '/sko_document_consent_fixture');
  assert.equal(destination.port, '5432');
  const pgModule = pathToFileURL(new URL(process.argv[2]).pathname).href;
  const pg = (await import(pgModule)).default;
  client = new pg.Client({connectionString: destination.href, connectionTimeoutMillis: 5000});
  await client.connect();
  check(Number((await client.query('show server_version_num')).rows[0].server_version_num) >= 170000, true, 'PG17 lower bound');
  check(Number((await client.query('show server_version_num')).rows[0].server_version_num) < 180000, true, 'PG17 upper bound');
  check((await client.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n, 0, 'Empty disposable database');
  check((await client.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not in('pg_catalog','information_schema') and n.nspname not like 'pg_toast%' and c.relkind in('r','p','v','m','S','f')")).rows[0].n,0,'No hidden private/application originals');
  for (const [path, expected] of Object.entries(manifest.source_git_blobs)) {
    check(blob(await fs.readFile(path)), expected, path);
  }

  phase = 'unchanged-existing-trade-fixture';
  await promisify(execFile)(process.execPath,
    ['tool/verify_trade_document_bound_seal_consent.mjs', pgModule, 'postgres'],
    {timeout: 180000, maxBuffer: 1024 * 1024, env: {...process.env,
      SKO_MONTHLY_PAYMENT_REVIEW_HOOK: 'contract-v1', SKO_TRADE_DOCUMENT_API_REVIEW_HOOK: 'contract-v1'}});

  const exec = sql => client.query(sql);
  const q = async (sql, values = []) => (await client.query(sql, values)).rows[0]?.v;
  const api = async (sql, values = []) => {
    await exec('set role authenticated');
    try {return await q(sql, values);} finally {await exec('reset role');}
  };
  const actor = async () => {
    await exec('reset role');
    await client.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false),set_config('test.blocked','false',false),set_config('test.invoice_view','true',false),set_config('test.invoice_manage','true',false)",
      [UA, JSON.stringify({sub: UA, role: 'authenticated', session_id: id(8001)})]);
  };
  await actor();
  await exec("update private.company_connections set status='accepted'");
  phase = 'synthetic-surrounding-schema';
  // These are fixture-only table shapes, not proposed production DDL. Existing
  // financial routine bodies below are separately checked against observations.
  await exec(`alter table companies add column tax_rate numeric default 10;
    alter table customers add column notes text default '';
    alter table invoices add column subtotal numeric default 0,add column automatic_calculation boolean default true,
      add column invoice_number text,add column issue_date date;
    alter table payment_certificates add column deductions integer default 0,add column net_amount integer,
      add column automatic_calculation boolean default true,add column updated_at timestamptz;
    create table private.expense_claims(id uuid primary key,company_id uuid,applicant_id uuid,applicant_name text,
      created_by uuid,incurred_on date,submitted_at timestamptz,description text,amount_yen integer,
      revision integer,approval text,withdrawn boolean default false,allocation text,counterparty_id uuid);
    create table private.expense_settlement_choices(claim_id uuid primary key references private.expense_claims(id),
      company_id uuid,method text,settlement_month date,approval_current boolean,cost_allocation_current boolean);
    create table sites(id uuid primary key,company_id uuid,customer_id uuid,name text,formal_name text);
    create table route_stops(id uuid primary key,route_assignment_id uuid,site_id uuid);
    create table daily_reports(id uuid primary key,company_id uuid,route_assignment_id uuid,site_id uuid,
      status text,signed_at timestamptz,signature_json jsonb,report_date date);
    create table daily_report_workers(report_id uuid,worker_id uuid);
    create table attendance_entries(id uuid primary key,company_id uuid,source_report_id uuid,
      route_assignment_id uuid,work_date date,site_id uuid,worker_id uuid,base_man_days numeric,
      work_category text,overtime_hours numeric,early_hours numeric,allowance_names text[]);
    create table attendance_verifications(id uuid primary key,company_id uuid,route_assignment_id uuid,
      worker_id uuid,work_date date,event_type text,daily_report_id uuid,site_id uuid,
      confirmed_at timestamptz,source_clock_in_id uuid);
    create table private.route_journey_captures(id uuid primary key,company_id uuid,source_clock_in_id uuid,
      route_assignment_id uuid,route_stop_id uuid,worker_id uuid,work_date date,recorded_at timestamptz);
    create table private.route_journey_visit_events(capture_id uuid,start_capture_id uuid,kind text,
      source_clock_in_id uuid,route_stop_id uuid);
    create table private.route_billing_quantity_requests(company_id uuid,worker_id uuid,work_date date,
      customer_id uuid,status text);`);
  const costs = await read('supabase/migrations/20261012142138_expense_document_original_costs.sql');
  const details = await read('supabase/migrations/20261010141814_expense_document_details.sql');
  const numbering = await read('supabase/migrations/20261005072500_invoice_number_stamps_and_terms.sql');
  const notices = await read('supabase/migrations/20260919213000_add_app_notifications.sql');
  const workflow = await read('supabase/migrations/20261005081500_invoice_approval_workflow.sql');
  const route = await read('supabase/migrations/20261013181708_route_signed_checkout_customer_billing.sql');
  const legacyRoute = await read('supabase/migrations/20261012053842_route_customer_billing_connection.sql');
  const direction = await read('docs/candidates/expense_payment_direction_v2_20261019.sql.review-only');
  await exec(table(costs, 'private.expense_amount_consumptions'));
  await exec(table(details, 'private.expense_document_snapshots'));
  await exec(table(numbering, 'private.invoice_number_counters'));
  await exec(table(notices, 'public.app_notifications'));
  for (const name of ['private.expense_amount_consumptions', 'private.expense_document_snapshots', 'private.invoice_number_counters', 'public.app_notifications']) {
    await exec(`alter table ${name} enable row level security;revoke all on ${name} from public,anon,authenticated,service_role`);
  }

  phase = 'exact-financial-source-installation';
  for (const name of ['private.expense_cost_scope_lock', 'private.expense_cost_components', 'private.expense_cost_finalize']) await exec(routine(costs, name));
  for (const name of ['private.expense_document_claims', 'private.capture_expense_document']) await exec(routine(details, name));
  for (const name of ['private.expense_payment_v2_envelope', 'private.expense_payment_v2_guard']) await exec(routine(direction, name));
  const patch = /do \$patch_finalize\$[\s\S]*?end \$patch_finalize\$;/i.exec(direction);
  assert.ok(patch);
  await exec(patch[0]);
  await exec(routine(numbering, 'private.assign_invoice_number_and_issue_date'));
  await exec(routine(notices, 'private.enqueue_notification'));
  await exec(routine(workflow, 'private.invoice_approval_rows_trigger'));
  const base = JSON.parse(await read('supabase/tests/fixtures/route_invoice_foundation_20261012.json'));
  await exec(base.manual_override);
  await exec(await read('tool/fixtures/trade_financial_brownfield/observed_invoice_blocked_guard.sql'));
  for (const name of ['private.route_signed_checkout_sources', 'private.route_signed_checkout_components', 'private.route_billing_invoice_blocked']) await exec(routine(route, name));
  await exec(routine(legacyRoute, 'private.route_billing_invoice_finalization_guard'));
  for (const [signature, expected] of Object.entries(manifest.actual_source_md5)) {
    check(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure', [signature]), expected, signature);
  }
  check(await q("select md5(prosrc) v from pg_proc where oid='public.approve_invoice_with_stamp_surname(uuid)'::regprocedure"),'1642933289661c4ec24f1bbdd85df669','Separate historical surname prerequisite source');
  await exec(`create trigger expense_cost_invoice_finalization before insert or update on invoices for each row execute function private.expense_cost_finalize();
    create trigger zz_expense_document_snapshot after insert or update on invoices for each row execute function private.capture_expense_document();
    create trigger invoice_approval_rows_after_write after insert or update on invoices for each row execute function private.invoice_approval_rows_trigger();
    create trigger invoices_assign_number_and_issue_date before insert or update on invoices for each row execute function private.assign_invoice_number_and_issue_date();
    create trigger invoice_manual_override_guard before update on invoices for each row execute function private.invoice_manual_override_guard();
    create trigger invoice_blocked_finalize_guard before insert or update on invoices for each row execute function private.invoice_blocked_finalize_guard();
    create trigger route_billing_invoice_finalization before insert or update on invoices for each row execute function private.route_billing_invoice_finalization_guard();
    create trigger expense_direction_v2_guard before insert or update or delete on payment_certificates for each row execute function private.expense_payment_v2_guard();`);
  for (const signature of Object.keys(manifest.actual_source_md5).filter(value => value.startsWith('private.'))) {
    await exec(`revoke all on function ${signature} from public,anon,authenticated,service_role`);
  }
  await client.query("insert into customers(id,company_id,name,billing_name,billing_address) values($1,$2,'乙会社','乙会社','乙住所')", [CUSTOMER,A]);
  await client.query("insert into trade_companies(id,company_id,customer_id,linked_company_id,trade_role,link_status) values($1,$2,$3,$4,'customer','linked')", [id(90005),A,CUSTOMER,B]);

  const seedClaim = async (number, month, allocation, party) => {
    const claim = id(number);
    await client.query("insert into private.expense_claims values($1,$2,$3,'合成社員',$4,$5,$5::date::timestamptz,'合成原価',1000,2,'approved',false,$6,$7)", [claim,A,id(90999),UA,month,allocation,party]);
    await client.query("insert into private.expense_settlement_choices values($1,$2,'cash',$3,true,true)", [claim,A,month]);
    return claim;
  };
  phase = 'negative-payment-original-baseline';
  const payment = id(90100), paymentClaim = await seedClaim(90101,'2026-06-01','subcontractor',PARTNER);
  await client.query(`insert into payment_certificates(id,company_id,partner_company_id,period_start,period_end,revision,status,gross_amount,deductions,net_amount,automatic_calculation,snapshot)
    values($1,$2,$3,'2026-06-01','2026-06-30',1,'finalized',0,1000,-1000,true,
    jsonb_build_object('calculation_rows','[]'::jsonb,'expense_cost_basis',jsonb_build_object('company_id',$2::uuid,'document_id',$1::uuid,'subject_id',$3::uuid,'month','2026-06','document_revision',1,'gross_before_expense_yen',0,'other_deductions_yen',0),
      'expense_cost_direction_v2',private.expense_payment_v2_envelope($2,$1,$3,'2026-06-01',1,1000,jsonb_build_array(jsonb_build_object('id',$4::uuid,'revision',2,'amount_yen',1000)))))`, [payment,A,PARTNER,paymentClaim]);
  await client.query(`insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
    values($1,'cost_recovery',$2,'paymentCertificate',$3,1,2,1000,'{}')`, [paymentClaim,A,payment]);
  const negativeOriginal = await q('select to_jsonb(p) v from payment_certificates p where id=$1',[payment]);
  const negativeLedger = await q('select to_jsonb(c) v from private.expense_amount_consumptions c where claim_id=$1',[paymentClaim]);
  const originalRows = await q(`select jsonb_build_object('invoices',(select coalesce(jsonb_agg(to_jsonb(i) order by id),'[]') from invoices i),
    'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from payment_certificates p),
    'consents',(select coalesce(jsonb_agg(to_jsonb(c) order by document_id,revision,company_id),'[]') from trade_document_consent_private.consents c)) v`);

  const prepare = async (number, month) => {
    await actor();const parent=id(number), claim=await seedClaim(number+1,month,'customer',CUSTOMER);
    const last = `${month.slice(0,7)}-${month.slice(5,7)==='09'?'30':'31'}`;
    const component = await q("select private.expense_cost_components('invoice',$1,$2,$3,$4,$5) v",[A,CUSTOMER,month,last,parent]);
    check(component.amount_yen,1000,'Correct customer cost amount');
    await client.query(`insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,subtotal,grand_total,tax,snapshot)
      values($1,$2,$3,$4,$5,clock_timestamp(),'draft',101000,111000,10000,jsonb_build_object('expense_extra_source_version',1,'expense_extra_amount_yen',1000,'expense_extra_claims',$6::jsonb))`,[parent,A,CUSTOMER,month,last,JSON.stringify(component.claims)]);
    const source = await q('select updated_at::text v from invoices where id=$1',[parent]);
    const defaults = await api("select public.trade_document_attachment_workspace('invoice',$1,$2) v",[parent,source]);
    const payload={...defaults.defaults,company_seal_enabled:false,company_seal_snapshot:null,issue_date:'2026-10-22',order_date:'2026-10-21',work_name:'金融連動合成工事',work_address:'東京都',acceptance_text:'上記注文内容を承諾します。',intro_text:'合成請負',payment_conditions:'翌月末',notes:''};
    await api("select public.save_trade_document_attachment('invoice',$1,$2,0,$3::jsonb) v",[parent,source,JSON.stringify(payload)]);
    const workspace = await api("select public.trade_document_confirmation_workspace('invoice',$1,$2) v",[parent,source]);
    const preview = await api('select public.preview_trade_document_confirmation($1,$2,$3,$4) v',[workspace.company_id,workspace.local_document_id,workspace.document_revision,workspace.kind]);
    return {parent,claim,workspace,preview,request:id(number+2)};
  };
  const confirm = x => api('select public.confirm_trade_document_with_seal($1::jsonb,$2,true,true) v',[JSON.stringify(x.preview.expected_command),x.request]);
  const state = async () => q(`select jsonb_build_object(
    'invoices',(select jsonb_agg(to_jsonb(x) order by id) from invoices x),
    'approvals',(select jsonb_agg(to_jsonb(x) order by invoice_id,position) from invoice_approvals x),
    'audit',(select jsonb_agg(to_jsonb(x) order by id) from invoice_approval_audit x),
    'consumptions',(select jsonb_agg(to_jsonb(x) order by claim_id,purpose) from private.expense_amount_consumptions x),
    'snapshots',(select jsonb_agg(to_jsonb(x) order by kind,document_id,revision) from private.expense_document_snapshots x),
    'notifications',(select jsonb_agg(to_jsonb(x) order by id) from app_notifications x),
    'counters',(select jsonb_agg(to_jsonb(x) order by company_id) from private.invoice_number_counters x),
    'consents',(select jsonb_agg(to_jsonb(x) order by document_id,revision,company_id) from trade_document_consent_private.consents x),
    'financial_receipts',(select jsonb_agg(to_jsonb(x) order by request_id) from trade_document_consent_private.financial_receipts x),
    'api_receipts',(select jsonb_agg(to_jsonb(x) order by company_id,request_id) from trade_document_confirmation_api_private.receipts x)) v`);

  phase = 'integrated-approval-consumption-and-retry';
  const success=await prepare(91000,'2026-07-01');
  check(await q('select count(*)::int v from private.expense_amount_consumptions where claim_id=$1',[success.claim]),0);
  check(await q('select count(*)::int v from app_notifications where action_id=$1',[success.parent]),1,'Actual pending approval notification');
  const approved=await confirm(success);
  check(approved.result.financial_approved,true);
  check(await q('select amount_yen v from private.expense_amount_consumptions where claim_id=$1',[success.claim]),1000,'Invoice recovery remains positive');
  check(await q('select count(*)::int v from private.expense_document_snapshots where document_id=$1',[success.parent]),0,'Approval timestamp is not status finalization');
  const after=await state();check(await confirm(success),approved);check(await state(),after,'Identical confirmation retry adds nothing');
  check(await q('select to_jsonb(p) v from payment_certificates p where id=$1',[payment]),negativeOriginal,'Saved -1000 unchanged');

  phase = 'late-consent-failure-rolls-back-financial-effects';
  const late=await prepare(92000,'2026-08-01'), lateBefore=await state();
  await exec("create function private.fixture_brownfield_late_failure() returns trigger language plpgsql as $$begin raise exception 'synthetic late financial receipt failure';end $$;create trigger fixture_brownfield_late_failure before insert on trade_document_consent_private.financial_receipts for each row execute function private.fixture_brownfield_late_failure()");
  await reject(()=>confirm(late),/synthetic late/);check(await state(),lateBefore,'Consent failure rolls back approval/audit/cost receipt');
  await exec('drop trigger fixture_brownfield_late_failure on trade_document_consent_private.financial_receipts');

  phase = 'explicit-status-snapshot-and-rollback';
  const snapshotBefore=await state();await exec('begin');
  await client.query("update invoices set status='finalized' where id=$1",[success.parent]);
  check(await q('select count(*)::int v from private.expense_document_snapshots where document_id=$1',[success.parent]),1,'Snapshot starts at actual status finalization');
  await exec('rollback');check(await state(),snapshotBefore,'Status snapshot rolls back with its transaction');

  phase = 'actual-blocked-status-guard-rolls-back-consumption';
  const calculationBefore=await state();
  await reject(()=>client.query("update invoices set calculation_blocked=true,status='finalized' where id=$1",[late.parent]),/勤務区分・現場単価/);
  check(await state(),calculationBefore,'Later blocked-status guard rolls back earlier cost trigger effects');

  phase = 'live-route-guard-refuses-approval-atomically';
  const blocked=await prepare(93000,'2026-09-01');
  const routeId=id(94000),site=id(94001),stop=id(94002),clock=id(94003),capture=id(94004),worker=id(94005);
  await client.query('insert into sites values($1,$2,$3,\'合成現場\',null)',[site,A,CUSTOMER]);
  await client.query('insert into route_stops values($1,$2,$3)',[stop,routeId,site]);
  await client.query("insert into attendance_verifications values($1,$2,$3,$4,'2026-09-01','clock_in',null,null,clock_timestamp(),null)",[clock,A,routeId,worker]);
  await client.query("insert into private.route_journey_captures values($1,$2,$3,$4,$5,$6,'2026-09-01',clock_timestamp())",[capture,A,clock,routeId,stop,worker]);
  await client.query("insert into private.route_journey_visit_events values($1,$1,'start',$2,$3)",[capture,clock,stop]);
  check(await q("select private.route_billing_invoice_blocked($1,$2,'2026-09-01','2026-09-30') v",[A,CUSTOMER]),true);
  const blockedBefore=await state();await reject(()=>confirm(blocked),/ルート|route|署名|退勤|請求/);check(await state(),blockedBefore,'Unverified route cannot consume or approve');
  check(await q('select to_jsonb(p) v from payment_certificates p where id=$1',[payment]),negativeOriginal);
  check(await q('select to_jsonb(c) v from private.expense_amount_consumptions c where claim_id=$1',[paymentClaim]),negativeLedger,'Prior payment consumption unchanged');
  const oldIds=originalRows.invoices.map(x=>x.id);
  check(await q('select jsonb_agg(to_jsonb(i) order by id) v from invoices i where id=any($1::uuid[])',[oldIds]),originalRows.invoices,'Prior financial rows unchanged');
  check(await q('select jsonb_agg(to_jsonb(p) order by id) v from payment_certificates p'),originalRows.payments,'All pre-existing payment rows unchanged');
  check(await q('select jsonb_agg(to_jsonb(c) order by document_id,revision,company_id) v from trade_document_consent_private.consents c where document_id=any($1::uuid[])',[Array.from(new Set(originalRows.consents.map(x=>x.document_id)))]),originalRows.consents,'Previously approved consent history unchanged');
  for(const [signature, expected] of Object.entries(manifest.actual_source_md5)) check(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[signature]),expected,'Source retained after cases');
  console.log(JSON.stringify({pass:true,checks,engine:'native PostgreSQL 17',actual_source_hashes_verified:true,
    synthetic_negative_payment_preserved:true,invoice_cost_recovery_yen:1000,approval_is_not_status_finalization:true,
    atomic_late_failure:true,identical_retry_no_duplicates:true,actual_route_guard_denied:true,
    real_gotrue_exercised:false,authorization_surroundings:'existing declared synthetic trade fixture',
    central_gate_installed:false,production_changed:false}));
}catch(error){
  console.error(JSON.stringify({pass:false,phase,code:error.code??null,message:String(error.message).slice(0,300),production_changed:false}));
  process.exitCode=1;
}finally{if(client)await client.end();}
