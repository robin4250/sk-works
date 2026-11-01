import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {setupExpenseCostFixture} from '../../fixtures/expense_cost_fixture.mjs';
import {fixtureTarget} from '../expense_manager_removal_20261101/fixture-target.mjs';
export const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export const info={company:id(1),worker:id(2),manager:id(3),applicant:id(9),sid:id(10),applicantSid:id(11),claim:id(100)};
export async function prepare(Client){
 const config={...fixtureTarget(),connectionTimeoutMillis:5000,query_timeout:17000};const c=new Client(config);
 try{
 await c.connect();await c.query("set statement_timeout='15s';set lock_timeout='4s';set idle_in_transaction_session_timeout='15s'");
 const target=(await c.query('select current_database() db,host(inet_server_addr()) ip,version() version')).rows[0];
 assert.equal(target.db,config.database);assert.equal(target.ip,process.env.SKO_EXPENSE_FIXTURE_SERVER_IP);assert.match(target.version,/PostgreSQL 17\.6\b/);
 assert.equal((await c.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','storage')")).rows[0].n,0);
 const db={exec:sql=>c.query(sql),query:(sql,p)=>c.query(sql,p)};
 await setupExpenseCostFixture(db);
 // Minimal synthetic dependency, not the deployed relation's schema/RLS proof.
 await c.query('create table private.account_deletion_access_restrictions(user_id uuid primary key)');
 await c.query(`CREATE OR REPLACE FUNCTION private.account_access_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$
`);
 assert.equal((await c.query("select md5(prosrc) value from pg_proc where oid='private.account_access_allowed()'::regprocedure")).rows[0].value,
  'aeca25db212c043c472334026bd98724');
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await c.query(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await c.query(`create table if not exists auth.users(id uuid primary key);
  alter table auth.users add column if not exists deleted_at timestamptz,
   add column if not exists is_anonymous boolean default false,add column if not exists banned_until timestamptz;
  create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
  create or replace function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object(
   'sub',current_setting('test.uid',true),'role',coalesce(nullif(current_setting('test.role',true),''),'authenticated'),
   'session_id',current_setting('test.sid',true),'exp',floor(extract(epoch from clock_timestamp()))+3600)$$;

 `);
 await c.query(`create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));
 alter table storage.objects enable row level security;
 grant usage on schema storage to authenticated,anon;
 grant select,insert,update,delete on storage.objects to authenticated,anon;
 create policy prior_broad_policy on storage.objects for all to public using(true) with check(true);`);
 await c.query(fs.readFileSync('supabase/migrations/20261012171205_expense_receipt_camera_attachments.sql','utf8'));
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
 await c.query(fs.readFileSync('docs/candidates/expense_manager_removal_receipt_binding_20261101.sql.review-only','utf8'));
 await c.query('update private.expense_manager_removal_state set enabled=true');
 return {config,admin:c};
 }catch(error){await c.end().catch(()=>{});throw error;}
}
