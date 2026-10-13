import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const definition=JSON.parse(fs.readFileSync('supabase/tests/fixtures/invoice_document_settings_20261013.json','utf8')).definition;
const company='10000000-0000-0000-0000-000000000001', actor='10000000-0000-0000-0000-000000000002';
try {
  await db.exec(`create role authenticated;create role service_role;create schema private;create schema auth;
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$ select coalesce(current_setting('test.view',true),'false')::boolean $$;
    create table public.company_members(company_id uuid,user_id uuid);
    create table public.companies(id uuid primary key, name text, company_seal_style text, company_seal_enabled boolean,
      postal_code text,address text,phone text,fax text,tax_rate numeric,default_welfare_rate numeric,invoice_template_title text,invoice_footer_note text);
    create table public.company_private_billing_settings(company_id uuid, bank_name text,bank_branch text,bank_account_type text,
      bank_account_number text,bank_account_holder text,invoice_subject text,invoice_contact_name text,payment_due_text text,invoice_logo_base64 text,invoice_seal_base64 text);
    insert into public.companies(id,name,company_seal_style,company_seal_enabled) values('${company}','検証会社','aoyagi_reisho',true);
    insert into public.company_members values('${company}','${actor}');`);
  await db.exec(definition);
  await db.exec('revoke all on function public.invoice_document_settings() from public;grant execute on function public.invoice_document_settings() to authenticated,service_role;');
  const before=(await db.query("select proacl::text acl,proconfig,prosecdef,md5(prosrc) body from pg_proc where oid='public.invoice_document_settings()'::regprocedure")).rows[0];
  assert.equal(before.body,'d22f3318cded6e6cc1bdf68ec16fbb74');
  const migration=fs.readFileSync('supabase/migrations/20261012161302_invoice_draft_seal_read_settings.sql','utf8');
  await db.exec(migration);
  const after=(await db.query("select proacl::text acl,proconfig,prosecdef from pg_proc where oid='public.invoice_document_settings()'::regprocedure")).rows[0];
  assert.deepEqual(after,{acl:before.acl,proconfig:before.proconfig,prosecdef:before.prosecdef});
  await db.exec(`set role authenticated;set test.uid='${actor}';set test.view='true';`);
  await assert.rejects(db.query('select * from public.companies'),/permission denied/);
  const result=(await db.query('select public.invoice_document_settings() value')).rows[0].value;
  assert.equal(result.company_id,company);assert.equal(result.company_name,'検証会社');assert.equal(result.company_seal_style,'aoyagi_reisho');
  await db.exec("set test.view='false'");
  await assert.rejects(db.query('select public.invoice_document_settings()'),/invoice view permission required/);
  await db.exec("set test.uid=''");
  await assert.rejects(db.query('select public.invoice_document_settings()'),/authentication required/);
  await db.exec('reset role');
  await assert.rejects(db.exec(migration),/changed; review before deployment/);
  console.log('PASS invoice-view RPC reads exact current draft seal without company SELECT; ACL/search path/auth predicate preserved and stale migration rejected');
} finally { await db.close(); }
