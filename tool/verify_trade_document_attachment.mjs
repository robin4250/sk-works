import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
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
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261014124714_monthly_trade_document_attachment.sql',import.meta.url),'utf8'));
const [c,c2,a,m,v,o,p,pc,inv,cu,pc2,pc0]=Array.from({length:12},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
await db.exec(`insert into companies values('${c}','自社','東京','1234567890123',true,'legacy'),('${c2}','他社','大阪','2222222222222',true,'legacy');
insert into company_members values('${c}','${a}','admin'),('${c}','${m}','manager'),('${c}','${v}','viewer'),('${c2}','${o}','admin');
insert into partner_companies values('${p}','${c}','下請け','神奈川','乙代表');insert into customers values('${cu}','${c}','発注元','発注元','東京');
insert into payment_certificates values('${pc}','${c}','${p}','2026-10-01','2026-10-31',1,'draft',null,110000,'{}'),('${pc2}','${c}','${p}','2026-11-01','2026-11-30',1,'draft',null,220000,'{}');
insert into invoices values('${inv}','${c}','${cu}','2026-10-01','2026-10-31','2026-10-14T12:00:00Z','draft',null,110000,10000,'{}');insert into payment_certificates values('${pc0}','${c}','${p}','2026-12-01','2026-12-31',1,'draft',null,0,'{}');set role authenticated;set test.uid='${a}';`);
const call=async(kind,id,rev)=>(await db.query('select public.trade_document_attachment_workspace($1,$2,$3) result',[kind,id,rev])).rows[0].result;
let w=await call('payment_certificate',pc,'1');assert.equal(w.attachment,null);assert.equal(w.defaults.tax_amount_yen,null);
const payload={...w.defaults,issue_date:'2026-10-15',work_name:'当月工事',work_address:'東京都',tax_amount_yen:10000,intro_text:'工事を発注します。',payment_conditions:'完了確認後、翌月末までに振込',notes:'',issuer:{...w.defaults.issuer,representative_name:'甲代表'},counterparty:{...w.defaults.counterparty,corporate_number:'9876543210987'}};
const save=(data=payload,version=0,id=pc,rev='1',kind='payment_certificate')=>db.query('select public.save_trade_document_attachment($1,$2,$3,$4,$5) result',[kind,id,rev,version,data]);
for(const data of [{...payload,tax_amount_yen:null},{...payload,tax_amount_yen:'10000'},{...payload,period_start:'2026-09-30'},{...payload,tax_amount_yen:110001},{...payload,month:'2026-09'},{...payload,kind:'acceptance'},{...payload,total_amount_yen:1},{...payload,issue_date:null},{...payload,issuer:{...payload.issuer,corporate_number:'123'}}])await assert.rejects(save(data));
for(const actor of [m,v,o]){await db.exec(`set test.uid='${actor}'`);await assert.rejects(save());}
await db.exec(`set test.uid='${v}'`);await assert.rejects(call('payment_certificate',pc,'1'),/権限/);
await assert.rejects(db.query('select public.trade_document_template($1,$2)',['payment_certificate',c]),/権限/);
await db.exec(`set test.uid='${m}'`);assert.equal((await call('payment_certificate',pc,'1')).can_manage,false);
await db.exec(`set test.uid='${a}'`);const first=(await save()).rows[0].result;assert.equal(first.version,1);
assert.deepEqual((await call('payment_certificate',pc,'1')).attachment,first);assert.equal((await call('payment_certificate',pc2,'1')).attachment,null);
await assert.rejects(save(),/更新/);await assert.rejects(db.query('select * from private.trade_document_attachments'),/permission denied/);
await db.exec(`reset role;update companies set name='変更後',company_seal_enabled=false where id='${c}';set role authenticated;`);
assert.deepEqual((await call('payment_certificate',pc,'1')).attachment,first);
await db.query('select public.trade_document_template($1,$2,$3,$4)',['payment_certificate',c,0,{notes:'新しい月の条件'}]);
assert.deepEqual((await call('payment_certificate',pc,'1')).attachment,first);assert.equal((await call('payment_certificate',pc2,'1')).template.notes,'新しい月の条件');
await db.exec(`reset role;update payment_certificates set status='finalized' where id='${pc}';set role authenticated;`);await assert.rejects(save({...payload,notes:'変更'},1),/確定/);
await db.exec(`reset role;update payment_certificates set revision=2,gross_amount=220000 where id='${pc}';set role authenticated;`);await assert.rejects(call('payment_certificate',pc,'1'),/更新/);assert.equal((await call('payment_certificate',pc,'2')).source_changed,true);
await db.exec(`reset role;update payment_certificates set status='draft' where id='${pc}';set role authenticated;`);
const updated=await call('payment_certificate',pc,'2');
const reviewed={...payload,...updated.defaults,issue_date:'2026-10-15',work_name:'更新後の当月工事',work_address:'東京',payment_conditions:'確認後振込',notes:'確認し直した内容',tax_amount_yen:20000,
 issuer:{...updated.defaults.issuer,representative_name:'甲代表'},counterparty:{...updated.defaults.counterparty,corporate_number:'9876543210987'}};
const second=(await save(reviewed,1,pc,'2')).rows[0].result;assert.equal(second.version,2);
assert.equal((await call('payment_certificate',pc,'2')).source_changed,false);
await assert.rejects(db.query('select * from private.trade_document_attachment_history'),/permission denied/);
await db.exec('reset role');
assert.deepEqual((await db.query('select payload from private.trade_document_attachment_history where subject_id=$1 and version=1',[pc])).rows[0].payload,first.payload);
await db.exec('set role authenticated');

await db.exec("set test.invoice_view='false'");await assert.rejects(call('invoice',inv,'2026-10-14T12:00:00Z'),/権限/);
await db.exec("set test.invoice_view='true';set test.invoice_manage='false'");
assert.equal((await call('invoice',inv,'2026-10-14T12:00:00Z')).can_manage,false);
await assert.rejects(db.query('select public.trade_document_template($1,$2)',['invoice',c]),/権限/);
await db.exec("set test.invoice_manage='true'");
w=await call('invoice',inv,'2026-10-14T12:00:00.000Z');assert.equal(w.defaults.tax_amount_yen,10000);
const acceptance={...w.defaults,order_date:'2026-10-15',issue_date:'2026-10-16',acceptance_text:'条件通り承諾します。',notes:'',issuer:{...w.defaults.issuer,representative_name:'乙代表'},counterparty:{...w.defaults.counterparty,corporate_number:'9876543210987',representative_name:'甲代表'}};
await db.exec("set test.invoice_manage='false'");await assert.rejects(save(acceptance,0,inv,'2026-10-14T12:00:00Z','invoice'),/管理者/);
await db.exec("set test.invoice_manage='true'");
assert.equal((await save(acceptance,0,inv,'2026-10-14T12:00:00Z','invoice')).rows[0].result.payload.kind,'acceptance');
await db.exec(`reset role;update invoices set updated_at='2026-10-14T13:00:00Z',approval_finalized_at=now(),invoice_seal_frozen=true,snapshot=jsonb_build_object('company_seal_snapshot',jsonb_build_object('version',1,'style','legacy','name','変更後')) where id='${inv}';set role authenticated;`);
assert.equal((await call('invoice',inv,'2026-10-14T13:00:00Z')).attachment.payload.kind,'acceptance');
assert.equal((await call('invoice',inv,'2026-10-14T13:00:00Z')).source_locked,true);
await assert.rejects(save(acceptance,1,inv,'2026-10-14T13:00:00Z','invoice'),/確定/);
if(db.concurrentSave){
 const next=await call('payment_certificate',pc2,'1');
 const candidate={...payload,...next.defaults,issue_date:'2026-11-01',period_start:'2026-11-01',period_end:'2026-11-30',work_name:'翌月工事',work_address:'東京',payment_conditions:'翌月末払い',notes:'',tax_amount_yen:20000,
   issuer:{...next.defaults.issuer,representative_name:'甲代表'},counterparty:{...next.defaults.counterparty,corporate_number:'9876543210987'}};
 const raced=await db.concurrentSave(a,['payment_certificate',pc2,'1',0,candidate]);
 assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(raced.filter(r=>r.status==='rejected'&&r.reason.code==='40001').length,3);
}
const zero=await call('payment_certificate',pc0,'1');
const explicitZero={...payload,...zero.defaults,issue_date:'2026-12-01',work_name:'零額の明示確認',work_address:'東京',payment_conditions:'合意額を確認',notes:'',tax_amount_yen:0,
 issuer:{name:zero.defaults.issuer.name,address:null,corporate_number:null,representative_name:null},counterparty:{name:zero.defaults.counterparty.name,address:'',corporate_number:'',representative_name:''}};
await db.exec(`reset role;update payment_certificates set calculation_blocked=true where id='${pc0}';set role authenticated;`);
await assert.rejects(save(explicitZero,0,pc0,'1'),/未確定/);
await db.exec(`reset role;update payment_certificates set calculation_blocked=false where id='${pc0}';set role authenticated;`);
assert.equal((await save(explicitZero,0,pc0,'1')).rows[0].result.payload.tax_amount_yen,0);
await db.exec(`set test.uid='${m}'`);
assert.equal((await db.query('select public.trade_document_template($1,$2) result',['payment_certificate',c])).rows[0].result.can_manage,true);
await db.query('select public.trade_document_template($1,$2,$3,$4)',['payment_certificate',c,1,{notes:'設定管理者の編集'}]);
await db.exec(`set test.uid='${a}'`);
await db.exec(`set test.blocked='true'`);await assert.rejects(call('invoice',inv,'2026-10-14T12:00:00Z'),/ログイン/);
await db.exec(`set test.blocked='false';set test.uid=''`);await assert.rejects(call('invoice',inv,'2026-10-14T12:00:00Z'));
await db.exec('reset role;set role anon');await assert.rejects(call('invoice',inv,'2026-10-14T12:00:00Z'),/permission denied/);
await db.exec(`reset role;set test.uid='${a}'`);
const templateMetadata=`select oid::text,proowner::text,proacl::text,prosecdef,proconfig from pg_proc where oid='private.trade_document_template(text,uuid,integer,jsonb)'::regprocedure`;
const beforeTemplateMetadata=(await db.query(templateMetadata)).rows;
const beforeAppendices=(await db.query('select * from private.trade_document_attachments order by subject_kind,subject_id')).rows;
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261020210553_payment_order_work_defaults.sql',import.meta.url),'utf8'));
assert.deepEqual((await db.query(templateMetadata)).rows,beforeTemplateMetadata);
assert.deepEqual((await db.query('select * from private.trade_document_attachments order by subject_kind,subject_id')).rows,beforeAppendices);
await db.exec('set role authenticated');
const templateCall=(kind,version,payload)=>db.query('select public.trade_document_template($1,$2,$3,$4) result',[kind,c,version,payload]);
const currentTemplate=(await templateCall('payment_certificate',null,null)).rows[0].result;
const workTemplate={work_name:'設定工事',work_address:'東京都の工事場所',notes:'特記事項'};
const updatedTemplate=(await templateCall('payment_certificate',currentTemplate.version,workTemplate)).rows[0].result;
assert.deepEqual(updatedTemplate.payload,workTemplate);
assert.deepEqual((await call('payment_certificate',pc2,'1')).template,workTemplate);
for(const payload of [{work_name:'x'.repeat(241)},{work_address:'x'.repeat(241)},{work_name:1},{work_address:null},{issuer:{name:'別会社'}},{total_amount_yen:1}])
 await assert.rejects(templateCall('payment_certificate',updatedTemplate.version,payload));
await assert.rejects(templateCall('invoice',0,workTemplate));
await assert.rejects(templateCall('payment_certificate',currentTemplate.version,workTemplate),/再読込/);
for(const actor of [v,o]){await db.exec(`set test.uid='${actor}'`);await assert.rejects(templateCall('payment_certificate',updatedTemplate.version,workTemplate),/権限/);}
await db.exec('reset role');
await assert.rejects(db.exec(await fs.readFile(new URL('../supabase/migrations/20261020210553_payment_order_work_defaults.sql',import.meta.url),'utf8')),/definition changed/);
await db.exec('rollback');
console.log('PASS order work defaults: saved/workspace roundtrip, field limits, scope, CAS, ACL/OID preservation, historical appendices unchanged');

console.log('PASS monthly appendices: permissions, NULL, CAS, month, source revision, finalized protection, immutable saved templates/seals, direct-table denial');await db.close();
