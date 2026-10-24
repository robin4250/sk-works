import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
const root = process.cwd();
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sko-png-deployment-proof-'));
fs.chmodSync(temp, 0o700);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company = id(1), owner = id(2);
let assertions = 0;
function ok(value) {assert.equal(value, true); assertions++;}
function artifact(mode, before, after) {
  const output = path.join(temp, `${mode}-${randomUUID()}.sql`);
  const args = ['tool/security/prepare_company_png_deployment_review.py', '--source-root', root, '--output', output];
  for (const [key, value] of [['before', before], ['after', after]]) {
    if (value != null) {
      const file = path.join(temp, `${key}-${randomUUID()}.json`);
      fs.writeFileSync(file, JSON.stringify(value), {mode:0o600, flag:'wx'});
      args.push(`--${key}`, file);
    }
  }
  args.push(mode);
  const result = spawnSync('python3', args, {cwd:root, encoding:'utf8'});
  if (result.status !== 0) throw Error(`offline PNG ${mode} generation failed`);
  return fs.readFileSync(output, 'utf8');
}
const observeSql = artifact('observer');
async function observe() {
  await db.exec('begin;');
  try {
    await db.exec(observeSql.slice(0, observeSql.lastIndexOf("select current_setting('sko.png_observation')")));
    const result = await db.query("select current_setting('sko.png_observation')::jsonb as observation");
    const value = result.rows[0].observation;
    await db.exec('rollback;');
    return value;
  } catch (error) {await db.exec('rollback;');throw error;}
}
async function rejected(sql) {
  let failed = false;
  try {await db.exec(sql);} catch (_) {failed = true; await db.exec('rollback;');}
  ok(failed);
}
try {
  await db.exec(`create schema auth;create schema private;create role anon;create role authenticated;create role service_role;
    grant usage on schema auth,private to authenticated;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function private.account_access_allowed() returns boolean language sql stable as $$select case when current_setting('test.access_null',true)='yes' then null else auth.uid() is not null end$$;
    create function private.aoyagi_reisho_name_supported(text) returns boolean language sql as $$select true$$;
    create table companies(id uuid primary key,name text,company_seal_style text default 'legacy');
    create table company_members(company_id uuid,user_id uuid,role text);
    create table invoices(id uuid primary key,amount integer,metadata jsonb);
    create table payment_certificates(id uuid primary key,amount integer,metadata jsonb);
    create table payroll_statements(id uuid primary key,amount integer,metadata jsonb);
    insert into companies(id,name) values('${company}','検証株式会社');
    insert into company_members values('${company}','${owner}','owner');
    insert into invoices values('${id(11)}',10000,'{"keep":"invoice"}');
    insert into payment_certificates values('${id(12)}',-1000,'{"keep":"payment"}');
    insert into payroll_statements values('${id(13)}',200000,'{"keep":"payroll"}');
    set test.uid='${owner}';`);
  const base = fs.readFileSync('supabase/migrations/20261010160154_company_seal_png_designs.sql','utf8');
  await db.exec(base.slice(base.indexOf('create or replace function private.document_company_seal_snapshot')));
  const before = await observe();
  const install = artifact('install', before);
  await db.exec("update public.invoices set amount=10001;");
  await rejected(install);
  ok((await db.query("select to_regclass('private.company_seal_png_versions') is null v")).rows[0].v);
  await db.exec('update public.invoices set amount=10000;');
  assert.deepEqual(await observe(), before); assertions++;
  const injected = install.replace(/commit;\s*$/i, "do $$begin raise exception 'fixture postflight failure';end $$;commit;");
  await rejected(injected);
  assert.deepEqual(await observe(), before); assertions++;
  await db.exec(install);
  const after = await observe();
  const restore = artifact('unused-restore', before, after);
  ok(Object.keys(after.relations).length === 7 && Object.keys(after.routines).length === 11);
  ok(after.data['private.company_seal_png_selection'].count === 0 && after.data['private.company_seal_png_versions'].count === 0);
  await db.exec(restore);
  assert.deepEqual(await observe(), before); assertions++;
  await db.exec(install);
  await db.exec("set test.access_null='yes';");
  await rejected(`select public.company_uploaded_seal_settings('${company}');`);
  await rejected(`select public.company_current_uploaded_seal('${company}');`);
  await rejected(`select public.save_company_uploaded_seal('${company}','検証株式会社',0,null,null,false);`);
  await db.exec("set test.access_null='no';set role authenticated;");
  const settings = (await db.query(`select public.company_uploaded_seal_settings('${company}') v`)).rows[0].v;
  ok(settings.available === true && settings.enabled === false && settings.revision === 0);
  await db.query(`select public.save_company_uploaded_seal('${company}','検証株式会社',0,null,null,false);`);
  await db.exec('reset role;');
  await rejected(restore);
  ok((await db.query('select count(*)::int n from private.company_seal_png_selection')).rows[0].n === 1);
  for (const name of ['public.invoices','public.payment_certificates','public.payroll_statements']) {
    assert.deepEqual((await observe()).data[name], before.data[name]); assertions++;
  }
  console.log(JSON.stringify({phase:'passed',assertions,synthetic:true,production_connected:false,
    proof:['stale install refused','late failure rollback','install-unused-restore equality','default selection OFF',
      'NULL account denied','authenticated settings and selection','used restore refused','financial originals unchanged']}));
} finally {
  await db.close();
  fs.rmSync(temp, {recursive:true, force:true});
}
