import fs from 'node:fs';
import assert from 'node:assert/strict';
const {setupExpenseCostFixture}=await import(process.argv[3] || './fixtures/expense_cost_fixture.mjs');
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),worker=id(2),actor=id(3),customer=id(4),partner=id(5);
const candidate='docs/candidates/expense_payment_direction_v2_20261019.sql.review-only';
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(`insert into companies(id,tax_rate) values('${company}',10);
 insert into company_members values('${company}','${actor}','owner');
 insert into workers(id,company_id,name,user_id,partner_company_id) values('${worker}','${company}','検証社員','${actor}','${partner}');
 insert into customers values('${customer}','${company}','検証取引先','');
 insert into partner_companies values('${partner}','${company}','検証下請け');
 insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1);
 set test.uid='${actor}';`);
 const row=async(month)=>(await db.query(`select * from payment_certificates where company_id='${company}' and partner_company_id='${partner}' and period_start='2026-${month}-01'`)).rows[0];
 async function approve(n,month,method='cash',category='subcontractor',party=partner){
 await db.exec(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
 values('${id(n)}','${company}','${worker}','検証社員','${actor}','2026-${month}-01','2026-${month}-01T01:00:00Z','検証経費',1000)`);
 return (await db.query(`select public.expense_confirm_review('${id(n+100)}','${id(n)}',1,'approve','${category}','${party}','${method}','') value`)).rows[0].value;
 }

 await approve(10,'07'); const legacy=await row('07');
 await db.exec(fs.readFileSync(candidate,'utf8'));
 await db.exec(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${company}'::uuid$$`);
 await approve(11,'08'); const directional=await row('08');
 assert.equal(directional.net_amount,-1000);
 const baseline=fs.readFileSync('supabase/migrations/20261008035432_certificate_canonical_snapshot_math.sql','utf8');
 await db.exec(baseline.slice(baseline.indexOf('CREATE OR REPLACE FUNCTION public.payment_certificate_detail_rows')));
 await db.exec(`alter table payment_certificates enable row level security;
 grant usage on schema public,private,auth to authenticated;
 grant select on payment_certificates,company_members to authenticated;
 create policy management_select on payment_certificates for select to authenticated using
 (exists(select 1 from company_members m where m.company_id=payment_certificates.company_id and m.user_id=auth.uid() and m.role in ('owner','admin','manager')));`);
 const before=(await db.query('select * from payment_certificates order by id')).rows;
 const metadata=async()=> (await db.query(`select proname,proowner,proacl,proconfig,prosecdef from pg_proc where oid in ('public.payment_certificate_detail_rows(uuid)'::regprocedure,'private.read_expense_document(text,uuid)'::regprocedure) order by oid`)).rows;
 const originalMetadata=await metadata();
 const sql=fs.readFileSync(process.argv[4] || 'docs/candidates/payment_expense_source_negotiation_20261020.sql.review-only','utf8');
 await db.exec(sql);
 assert.deepEqual(await metadata(),originalMetadata,'reader privileges unchanged');
 async function asActor(headers,query,uid=actor){
  await db.exec(`set role authenticated; select set_config('test.uid','${uid}',false); select set_config('request.headers','${headers.replaceAll("'","''")}',false)`);
  try {return (await db.query(query)).rows;} finally {await db.exec('reset role');}
 }
 const list='select id from payment_certificates order by id';
 for(const h of ['', '{}','{"x-sko-payment-source-version":"1"}','{"x-sko-payment-source-version":2}','[]','broken']){
  assert.deepEqual((await asActor(h,list)).map(x=>x.id),[legacy.id],`legacy reader ${h}`);
  await assert.rejects(asActor(h,`select * from public.payment_certificate_detail_rows('${directional.id}')`),/Update SKO/);
  await assert.rejects(asActor(h,`select public.read_expense_document('paymentCertificate','${directional.id}')`),/Update SKO/);
 }
 const supported='{"x-sko-payment-source-version":"2"}';
 assert.equal((await asActor(supported,list)).length,2);
 assert.equal((await asActor(supported,`select public.read_expense_document('paymentCertificate','${directional.id}') value`))[0].value.expense_cost_direction_v2.amount_yen,1000);
 await asActor(supported,`select * from public.payment_certificate_detail_rows('${directional.id}')`);
 assert.deepEqual(await asActor(supported,list,id(99)),[],'header grants no membership');
 await assert.rejects(asActor(supported,`select * from public.payment_certificate_detail_rows('${directional.id}')`,id(99)),/permission required/);
 await assert.rejects(asActor(supported,`select public.read_expense_document('paymentCertificate','${directional.id}')`,id(99)),/access denied/);
 assert.deepEqual((await db.query('select * from payment_certificates order by id')).rows,before);
 await assert.rejects(db.exec(sql),/already installed/); await db.exec('rollback');
 console.log('PASS payment negotiation: legacy table/RPC, exact header, membership, unchanged documents/privileges. Real HTTP/JWT unverified.');
} finally {await db.close();}
