import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {setupExpenseCostFixture} from '../../fixtures/expense_cost_fixture.mjs';
import {fixtureTarget} from '../expense_manager_removal_20261101/fixture-target.mjs';
export const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export const info={company:id(1),worker:id(2),manager:id(3),applicant:id(9),sid:id(10),applicantSid:id(11),claim:id(100)};
export async function prepare(Client){
 const config=fixtureTarget();const c=new Client(config);await c.connect();
 const target=(await c.query('select current_database() db,host(inet_server_addr()) ip,version() version')).rows[0];
 assert.equal(target.db,config.database);assert.equal(target.ip,process.env.SKO_EXPENSE_FIXTURE_SERVER_IP);assert.match(target.version,/PostgreSQL 17\.6\b/);
 assert.equal((await c.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','storage')")).rows[0].n,0);
 const db={exec:sql=>c.query(sql),query:(sql,p)=>c.query(sql,p)};
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await c.query(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await c.query(`create table if not exists auth.users(id uuid primary key);
  alter table auth.users add column if not exists deleted_at timestamptz,
   add column if not exists is_anonymous boolean default false,add column if not exists banned_until timestamptz;
  create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
  create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object(
   'sub',current_setting('test.uid',true),'role',coalesce(nullif(current_setting('test.role',true),''),'authenticated'),
   'session_id',current_setting('test.sid',true),'exp',floor(extract(epoch from clock_timestamp()))+3600)$$;
  alter table private.expense_claims add column receipt_object_path text;
 `);
 await c.query(fs.readFileSync('supabase/migrations/20260919213000_add_app_notifications.sql','utf8'));
 const company=id(1),worker=id(2),manager=id(3),applicant=id(9),sid=id(10),applicantSid=id(11);
 await c.query(`insert into auth.users(id) values('${manager}'),('${applicant}'),('${id(8)}');
  insert into auth.sessions values('${sid}','${manager}',null),('${applicantSid}','${applicant}',null);
  insert into companies(id,tax_rate) values('${company}',10),('${id(7)}',10);
  insert into company_members values('${company}','${manager}','owner'),('${company}','${applicant}','viewer');
  insert into workers(id,company_id,name,user_id) values('${worker}','${company}','本人','${applicant}');
  insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${manager}']::uuid[],1);
  set test.uid='${manager}';set test.sid='${sid}';grant usage on schema private,auth to authenticated;
 `);

 const source=fs.readFileSync('docs/candidates/expense_manager_removal_20261101.sql.review-only');
 assert.equal(createHash('sha256').update(source).digest('hex'),'b2584677c81e50fa44cfbbc544de9fb6a4377e089875b5db09701f26953252e2');
 await c.query(source.toString('utf8'));
 await c.query('update private.expense_manager_removal_state set enabled=true');
 await c.query(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,receipt_object_path)
 values($1,$2,$3,'Bridge applicant',$4,date_trunc('month',current_date)::date,'Native bridge receipt',1234,'retained/bridge-original.png')`,[info.claim,info.company,info.worker,info.applicant]);
 return {config,admin:c};
}
