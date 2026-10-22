import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
try {
await db.exec(`create role anon;create role authenticated;create role service_role;create schema private;create schema auth;
create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed()returns boolean language sql as $$select coalesce(current_setting('test.blocked',true),'false')<>'true'$$;
create table companies(id uuid primary key,name text,address text,corporate_number text,company_seal_enabled boolean,company_seal_style text);
create table company_members(company_id uuid,user_id uuid,role text);
create function private.has_company_feature(cid uuid,feature text)returns boolean language sql as $$
 select exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid()) and
 case feature when 'can_view_invoices' then coalesce(current_setting('test.invoice_view',true),'true')='true'
 when 'can_manage_invoices' then coalesce(current_setting('test.invoice_manage',true),'true')='true' else false end $$;
create table partner_companies(id uuid primary key,company_id uuid,name text,address text,president_name text);
create table customers(id uuid primary key,company_id uuid,name text,billing_name text,billing_address text);
create table payment_certificates(id uuid primary key,company_id uuid,partner_company_id uuid,period_start date,period_end date,revision int,status text,finalized_at timestamptz,gross_amount int,snapshot jsonb,calculation_blocked boolean default false);
create table invoices(id uuid primary key,company_id uuid,customer_id uuid,billing_period_start date,billing_period_end date,updated_at timestamptz,status text,finalized_at timestamptz,grand_total int,tax int,snapshot jsonb,calculation_blocked boolean default false,approval_finalized_at timestamptz,invoice_seal_frozen boolean default false);
create function private.document_company_seal_snapshot(jsonb,uuid,boolean)returns jsonb language sql as $$select jsonb_build_object('company_seal_snapshot',jsonb_build_object('version',1,'style','legacy','name',name))from public.companies where id=$2$$;
grant usage on schema private,auth to authenticated;`);

const migration=await fs.readFile('supabase/migrations/20261014124714_monthly_trade_document_attachment.sql','utf8');
const baseSource=migration.match(/create function private\.trade_document_source\([\s\S]*?end \$\$;/)?.[0];
if (!baseSource) throw new Error('Public source fixture anchor changed');
await db.exec("create table private.trade_document_attachments(subject_kind text,subject_id uuid,company_id uuid,payload jsonb default '{\"frozen\":true}');create table private.partner_company_profile_extensions(company_id uuid primary key,representative_name text);create table trade_companies(id uuid primary key,company_id uuid,customer_id uuid,partner_company_id uuid,trade_role text,address text,corporate_number text,representative_name text)");
await db.exec(baseSource);
await db.exec('revoke all on function private.trade_document_source(text,uuid,text) from public');
for(const name of ['payment_order_tax_from_snapshot_20261020','payment_order_directory_party_source_20261021','payment_order_own_representative_20261021']) {
 await db.exec(await fs.readFile('docs/candidates/'+name+'.sql.review-only','utf8'));
}
const [c,other,user,cu,inv,partner,pay,tid]=Array.from({length:8},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
await db.exec(`insert into companies values('${c}','自社','東京','1234567890123',true,'legacy');insert into company_members values('${c}','${user}','admin');insert into customers values('${cu}','${c}','発注元','請求先','原住所');insert into partner_companies values('${partner}','${c}','協力会社','協力住所','代表乙');insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,grand_total,tax,snapshot) values('${inv}','${c}','${cu}','2026-10-01','2026-10-31','2026-10-14T12:00:00Z','draft',110000,10000,'{}');insert into payment_certificates values('${pay}','${c}','${partner}','2026-10-01','2026-10-31',1,'draft',null,110000,'{"tax":10000}',false);set test.uid='${user}';`);
let checks=0;const eq=(a,b)=>{assert.deepEqual(a,b);checks++};
const call=async(kind='invoice',id=inv,rev='2026-10-14T12:00:00Z')=>(await db.query('select private.trade_document_source($1,$2,$3) v',[kind,id,rev])).rows[0].v;
const metadata=async()=>(await db.query("select to_jsonb(p)-'prosrc' v from pg_proc p where p.oid='private.trade_document_source(text,uuid,text)'::regprocedure")).rows;
const metadataBefore=await metadata();
const before=await call();const payBefore=await call('payment_certificate',pay,'1');
const financial=await db.query('select to_jsonb(i) row from invoices i');
await db.exec('create table private.trade_document_attachment_history(payload jsonb);create table private.partner_company_profile_audit(before_value jsonb,after_value jsonb)');
await db.exec("insert into private.trade_document_attachment_history values('{\"saved\":true}');insert into private.partner_company_profile_audit values('{}','{}')");
const observe=async()=>(await db.query(await fs.readFile('docs/candidates/invoice_party_representatives_verify.read-only.sql','utf8'))).rows[0].observation;
const observationBefore=await observe();
await db.exec(await fs.readFile('docs/candidates/invoice_party_representatives.sql.review-only','utf8'));
eq(await call(),before);eq(await metadata(),metadataBefore);
const observationAfter=await observe();
eq(observationAfter.tables,observationBefore.tables);
eq(observationAfter.source_catalog.attributes,observationBefore.source_catalog.attributes);
eq(observationBefore.source_catalog.source_md5,'a24d433cb49462869a06d51081562a43');
eq(observationAfter.source_catalog.source_md5,'ebcc70935938482054943560390038b2');
const exceptBody=rs=>rs.map(r=>({...r,body_md5:null}));
eq(exceptBody(observationAfter.routines),exceptBody(observationBefore.routines));
await db.query('insert into private.partner_company_profile_extensions values($1,$2)',[c,'自社代表']);
eq((await call()).defaults.issuer.representative_name,'自社代表');
await db.query('insert into trade_companies values($1,$2,$3,null,$4,$5,$6,$7)',[tid,c,cu,'customer','登録住所','9876543210987','甲代表']);
const configured=await call();eq(configured.defaults.counterparty,{name:'請求先',address:'登録住所',corporate_number:'9876543210987',representative_name:'甲代表'});
for(const key of ['source_fingerprint','source_revision','source_locked'])eq(configured[key],before[key]);
eq(configured.defaults.total_amount_yen,before.defaults.total_amount_yen);eq(configured.defaults.tax_amount_yen,before.defaults.tax_amount_yen);
eq(await call('payment_certificate',pay,'1'),{...payBefore,defaults:{...payBefore.defaults,issuer:{...payBefore.defaults.issuer,representative_name:'自社代表'}}});
await db.exec("set test.invoice_manage='false'");eq(await call(),{...before,can_manage:false,template_can_view:false});await db.exec("set test.invoice_manage='true'");
for(const role of ['subcontractor','both']){await db.query('update trade_companies set trade_role=$1',[role]);eq((await call()).defaults.counterparty,role==='both'?configured.defaults.counterparty:before.defaults.counterparty)}
await db.query('insert into trade_companies values($1,$2,$3,null,$4,$5,$6,$7)',[other,c,cu,'customer','誤結合','1111111111111','重複']);
eq((await call()).defaults.counterparty,before.defaults.counterparty);
await db.query('update trade_companies set company_id=$1 where id=$1',[other]);eq((await call()).defaults.counterparty,configured.defaults.counterparty);
await db.query('update trade_companies set customer_id=null where id=$1',[tid]);eq((await call()).defaults.counterparty,before.defaults.counterparty);
await db.query('update trade_companies set customer_id=$1,address=$2,corporate_number=$3,representative_name=$4 where id=$5',[cu,'x'.repeat(241),'123','x'.repeat(81),tid]);eq((await call()).defaults.counterparty,before.defaults.counterparty);
await db.query('insert into private.trade_document_attachments(subject_kind,subject_id,company_id) values($1,$2,$3)',['invoice',inv,c]);const childBefore=await db.query('select md5(to_jsonb(a)::text) hash from private.trade_document_attachments a');eq((await call()).defaults,before.defaults);eq(await db.query('select md5(to_jsonb(a)::text) hash from private.trade_document_attachments a'),childBefore);
await db.exec('delete from private.trade_document_attachments');
for(const lock of ["status='finalized'","status='draft',finalized_at=now()","finalized_at=null,approval_finalized_at=now()","approval_finalized_at=null,invoice_seal_frozen=true"]){await db.exec('update invoices set '+lock);const locked=await call();eq(locked.defaults,{...before.defaults,issuer:{...before.defaults.issuer,representative_name:'自社代表'}});eq(locked.source_locked,true)}
await db.exec("update invoices set status='draft',finalized_at=null,approval_finalized_at=null,invoice_seal_frozen=false");eq(await db.query('select to_jsonb(i) row from invoices i'),financial);
await db.exec("set test.invoice_view='false'");await assert.rejects(call(),e=>e.code==='42501');checks++;
await db.exec("set test.invoice_view='true';set test.blocked='true'");await assert.rejects(call(),e=>e.code==='42501');checks++;
await db.exec("set test.blocked='false'");await assert.rejects(call('invoice',inv,'2026-10-15T12:00:00Z'),e=>e.code==='40001');checks++;
await assert.rejects(db.exec(await fs.readFile('docs/candidates/invoice_party_representatives.sql.review-only','utf8')),e=>e.code==='55000');checks++;await db.exec('rollback');
await db.exec(await fs.readFile('docs/candidates/invoice_party_representatives_restore.sql.review-only','utf8'));
eq(await call(),before);eq(await metadata(),metadataBefore);eq(await db.query('select to_jsonb(i) row from invoices i'),financial);
await assert.rejects(db.exec(await fs.readFile('docs/candidates/invoice_party_representatives_restore.sql.review-only','utf8')),e=>e.code==='55000');checks++;await db.exec('rollback');
await db.exec(await fs.readFile('docs/candidates/invoice_party_representatives.sql.review-only','utf8'));
eq((await call()).defaults.issuer.representative_name,'自社代表');
console.log('PASS '+checks+' invoice source representative checks; synthetic isolated DB only');
} finally { await db.close(); }
