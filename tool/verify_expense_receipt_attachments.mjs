import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 // Synthetic Storage catalog and permissive old policy: test our new bucket's
 // authorization boundary independently from existing unrelated bucket policies.
 await db.exec(`create schema storage;
  create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));
  alter table storage.objects enable row level security;
  grant usage on schema storage to authenticated,anon;
  grant select,insert,update,delete on storage.objects to authenticated,anon;
  create policy prior_broad_policy on storage.objects for all to public using(true) with check(true);`);
 await db.exec(fs.readFileSync('supabase/migrations/20261012171205_expense_receipt_camera_attachments.sql','utf8'));
 const company=id(1),worker=id(2),actor=id(3),claim=id(4),reviewer=id(5),sha='a'.repeat(64);
 await db.exec(`insert into companies(id) values('${company}');
  insert into company_members values('${company}','${actor}','owner'),('${company}','${reviewer}','manager');
  insert into workers(id,company_id,name,user_id) values('${worker}','${company}','本人','${actor}');
  insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${reviewer}']::uuid[],1);
  set role authenticated;set test.uid='${actor}';`);
 const prepare=async(hash=sha)=>(await db.query(`select public.expense_prepare_receipt('${claim}','${company}','${worker}','${hash}',4,'image/jpeg') value`)).rows[0].value;
 const reserved=await prepare();assert.equal(reserved.attached,false);assert.equal(reserved.uploaded,false);
 assert.deepEqual(await prepare(),reserved);
 await assert.rejects(prepare('b'.repeat(64)),/fixed receipt differs/);
 const submit=async()=>(await db.query(`select public.expense_personal_submit_with_receipt('${claim}','${company}','${worker}','2026-09-30','領収書撮影',1234) value`)).rows[0].value;
 await assert.rejects(submit(),/領収書の保存/);
 await db.exec(`insert into storage.objects(bucket_id,name,metadata) values('expense-receipts','${reserved.object_path}','{"size":4,"mimetype":"image/jpeg"}');`);
 assert.equal((await prepare()).uploaded,true);
 assert.equal((await db.query(`select count(*)::int n from storage.objects where bucket_id='expense-receipts'`)).rows[0].n,1);
 const submitted=await submit();assert.equal(submitted.receipt_object_path,reserved.object_path);
 assert.deepEqual(await submit(),submitted,'fixed submission and attachment receipt replay');
 assert.deepEqual((await db.query(`select public.expense_personal_exact_with_receipt('${claim}') value`)).rows[0].value,submitted);
 await db.exec(`update storage.objects set metadata='{}' where name='${reserved.object_path}';delete from storage.objects where name='${reserved.object_path}';`);
 assert.equal((await db.query(`select count(*)::int n from storage.objects where name='${reserved.object_path}'`)).rows[0].n,1,'generic policies cannot delete attached receipt');
 assert.equal((await prepare()).uploaded,true,'generic policies cannot overwrite receipt');
 await db.exec(`set test.uid='${reviewer}';`);
 assert.equal((await db.query(`select count(*)::int n from storage.objects where bucket_id='expense-receipts'`)).rows[0].n,1,'selected reviewer can read attached receipt');
 await assert.rejects(prepare(),/own active worker required/);
 await db.exec(`set test.uid='${id(999)}';`);
 assert.equal((await db.query(`select count(*)::int n from storage.objects where bucket_id='expense-receipts'`)).rows[0].n,0,'other actor cannot read despite broad policy');
 await db.exec('reset role');
 assert.equal((await db.query("select public from storage.buckets where id='expense-receipts'")).rows[0].public,false);
 assert.equal((await db.query(`select count(*)::int n from private.expense_claims where id='${claim}'`)).rows[0].n,1);
 assert.equal((await db.query(`select count(*)::int n from payroll_statements`)).rows[0].n,0);
 console.log('PASS private receipt reservation, upload failure without claim write, fixed submission attach retry, applicant/reviewer scope, generic-policy isolation, no overwrite/delete, no payroll writes');
}finally{await db.close();}
