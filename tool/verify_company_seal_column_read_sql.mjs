// Disposable PostgreSQL fixture. No production connection or real company data.
import {readFile,readdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(resolve(process.argv[2])).href);
const migrationArg=process.argv.indexOf('--migration');
const candidates= (await readdir(resolve(root,'supabase/migrations'))).filter(p=>p.endsWith('_grant_company_seal_style_read.sql'));
const migration=migrationArg>=0?resolve(process.argv[migrationArg+1]):resolve(root,'supabase/migrations',candidates[0]??'MISSING');
if(migrationArg<0) assert.equal(candidates.length,1,'Expected exactly one seal-style column GRANT migration');
const db=new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
const user='20000000-0000-0000-0000-000000000001';
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select auth.uid() is not null and current_setting('test.blocked',true) is distinct from 'yes'$$;
 grant usage on schema auth,private to authenticated;
 create table companies(id uuid primary key,name text,postal_code text,address text,phone text,fax text,email text,
 invoice_registration_number text,created_at timestamptz,updated_at timestamptz,tax_rate numeric,default_unit_price numeric,
 default_invoice_detail_mode text,default_welfare_rate numeric,invoice_template_title text,invoice_footer_note text,
 bank_account_number text,company_seal_enabled boolean not null default true,company_seal_style text not null default 'legacy');
 create table company_members(company_id uuid,user_id uuid);
 insert into companies(id,name,bank_account_number,company_seal_style) values('${company}','Fixture Company','PRIVATE_BANK','aoyagi_reisho'),('${other}','Other Company','OTHER_PRIVATE_BANK','legacy');
 insert into company_members values('${company}','${user}');
 alter table companies enable row level security;
 create policy company_member_read on companies for select to authenticated using(exists(select 1 from company_members m where m.company_id=companies.id and m.user_id=(select auth.uid())));
 create policy account_access_guard on companies as restrictive for select to authenticated using(private.account_access_allowed());
 grant select on company_members to authenticated;`);
 await db.exec(await readFile(resolve(root,'supabase/migrations/20260921050111_restrict_company_select_columns.sql'),'utf8'));
 await db.exec('grant select(company_seal_enabled) on companies to authenticated');
 const policies=async()=> (await db.query("select polname,polcmd,polpermissive,polroles::text,pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) checks from pg_policy where polrelid='companies'::regclass order by polname")).rows;
 const acl=async()=> (await db.query("select attname,attacl::text from pg_attribute where attrelid='companies'::regclass and attnum>0 and not attisdropped order by attnum")).rows;
 const beforePolicies=await policies(),beforeAcl=await acl();
 const beforeTable=(await db.query("select relacl::text,relrowsecurity,relforcerowsecurity from pg_class where oid='companies'::regclass")).rows;
 await db.exec(`set test.uid='${user}';set role authenticated`);
 const fields='id,name,postal_code,address,phone,fax,company_seal_enabled,company_seal_style';
 await assert.rejects(db.query(`select ${fields} from companies where id=$1`,[company]),e=>e.code==='42501');
 await db.exec('reset role');
 await db.exec(await readFile(migration,'utf8'));
 assert.deepEqual(await policies(),beforePolicies,'Row policies must remain unchanged');
 assert.deepEqual((await db.query("select relacl::text,relrowsecurity,relforcerowsecurity from pg_class where oid='companies'::regclass")).rows,beforeTable,'Table ACL and RLS flags must remain unchanged');
 const afterAcl=await acl();
 assert.deepEqual(afterAcl.filter(c=>c.attname!=='company_seal_style'),beforeAcl.filter(c=>c.attname!=='company_seal_style'),'Other column ACLs must remain unchanged');
 assert.equal((await db.query("select has_column_privilege('authenticated','companies','company_seal_style','SELECT') ok")).rows[0].ok,true);
 for(const role of ['anon','authenticated']) {
  for(const privilege of ['INSERT','UPDATE','REFERENCES']) assert.equal((await db.query('select has_column_privilege($1,$2,$3,$4) ok',[role,'companies','company_seal_style',privilege])).rows[0].ok,false);
 }
 await db.exec('set role authenticated');
 const own=(await db.query(`select ${fields} from companies where id=$1`,[company])).rows;
 assert.equal(own.length,1);assert.equal(own[0].company_seal_style,'aoyagi_reisho');assert.equal(own[0].company_seal_enabled,true);
 assert.equal((await db.query(`select ${fields} from companies where id=$1`,[other])).rows.length,0);
 await db.exec("set test.blocked='yes'");assert.equal((await db.query(`select ${fields} from companies`)).rows.length,0);
 await db.exec("set test.blocked='no'");
 for(const query of ['select bank_account_number from companies','select * from companies',"update companies set company_seal_style='legacy'"]) await assert.rejects(db.query(query),e=>e.code==='42501');
 await db.exec('reset role;set role anon');
 await assert.rejects(db.query('select company_seal_style from companies'),e=>e.code==='42501');
 console.log('PASS seal column read: former 42501 fixed, explicit payment fields readable, foreign/blocked rows hidden, anon/bank/select-star/mutation denied, existing RLS and other ACLs unchanged');
} finally {await db.close();}
