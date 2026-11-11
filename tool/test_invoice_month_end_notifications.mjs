// Disposable PGlite only; never connects to Supabase or sends production notices.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const check=async(sql,want,label)=>{const got=(await db.query(sql)).rows[0].v;if(got!==want)throw Error(label+': '+got+' != '+want);};
const reject=async(sql,label)=>{let failed=false;try{await db.exec(sql);}catch{failed=true;}if(!failed)throw Error('expected rejection: '+label);};
try{
 await db.exec("-- Local isolated SQL harness: prerequisite fixtures emulate the existing schema.\n-- Run only against a fresh disposable PostgreSQL/PGlite instance; never production.\ncreate role anon; create role authenticated; create role service_role;\ncreate schema auth; create schema private;\ncreate function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;\ncreate table auth.users(id uuid primary key);\ncreate table public.companies(id uuid primary key);\ncreate table public.company_members(company_id uuid,user_id uuid,role text);\ncreate table public.user_profiles(user_id uuid,display_name text);\ncreate function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$\nselect exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role in ('owner','admin','manager'))$$;\ncreate table public.invoices(id uuid primary key,company_id uuid references public.companies,customer_id uuid,\n billing_period_start date,billing_period_end date,status text,subtotal int,tax int,welfare_amount int,\n adjustments int,grand_total int,detail_mode text,snapshot jsonb,updated_at timestamptz,finalized_at timestamptz);\ncreate table public.invoice_site_calculations(id uuid primary key,invoice_id uuid references public.invoices on delete cascade,subtotal int);\ncreate table public.invoice_detail_lines(id uuid primary key,invoice_site_calculation_id uuid references public.invoice_site_calculations on delete cascade,amount int);\ncreate table public.app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);\ncreate or replace function private.enqueue_notification(p_company_id uuid,p_recipient_user_id uuid,p_kind text,p_title text,p_body text default null,p_action_key text default null,p_action_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $actual$\ndeclare\n  v_id uuid;\nbegin\n  insert into public.app_notifications(\n    company_id,\n    recipient_user_id,\n    kind,\n    title,\n    body,\n    action_key,\n    action_id\n  )\n  values(\n    p_company_id,\n    p_recipient_user_id,\n    coalesce(nullif(trim(p_kind), ''), 'info'),\n    p_title,\n    p_body,\n    p_action_key,\n    p_action_id\n  )\n  returning id into v_id;\n\n  return v_id;\nend;\n$actual$;\ninsert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004');\ninsert into public.companies values('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');\ninsert into public.company_members values\n('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner'),\n('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','member'),\n('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','member'),\n('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','owner');\n\nalter table auth.users add column banned_until timestamptz;\nalter table auth.users add column deleted_at timestamptz;\ncreate table private.account_deletion_access_restrictions(user_id uuid primary key);\ncreate function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as 'select 123';\ncreate function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as\n'select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())';\ncreate or replace function private.check_account_access() returns void language plpgsql security definer set search_path='' as $actual$\ndeclare subject uuid:=auth.uid();\nbegin\n if subject is not null then\n  -- A fresh snapshot after acquiring the lock is essential. A transaction with\n  -- a fixed snapshot could miss a restriction committed while it was starting.\n  if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then\n   raise sqlstate '42501' using message='account_access_isolation_unsupported';\n  end if;\n  if not pg_catalog.pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(subject)) then\n   raise sqlstate '42501' using message='account_access_transition';\n  end if;\n  -- This is a separate command inside a VOLATILE function, hence a fresh\n  -- READ COMMITTED snapshot. The shared lock lasts through the entire request.\n  if not private.account_access_allowed() then\n   raise sqlstate '42501' using message='account_access_restricted';\n  end if;\n end if;\n perform set_config('sko.account_access_hook_ran','true',true);\n perform set_config('sko.account_access_barrier_ran','data-api-v1',true);\nend $actual$;\ncreate or replace function public.account_server_access_allowed(p_user uuid) returns boolean language sql security definer set search_path='' as $actual$\n select p_user is not null and exists(select 1 from auth.users where id=p_user\n  and (banned_until is null or banned_until<=now()))\n and not exists(select 1 from private.account_deletion_access_restrictions where user_id=p_user)\n$actual$;\n");
 await db.exec(read('supabase/migrations/20261005081500_invoice_approval_workflow.sql'));
 await db.exec(read('supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql'));
 const staged=read('tool/staged/invoice_month_end_approval_notifications.sql');
 await db.exec(staged); await db.exec(staged);
 const c='10000000-0000-0000-0000-000000000001', c2='10000000-0000-0000-0000-000000000002';
 const u='00000000-0000-0000-0000-000000000001', u2='00000000-0000-0000-0000-000000000002';
 const inv='20000000-0000-0000-0000-000000000001', inv2='20000000-0000-0000-0000-000000000002';
 await db.exec("select set_config('request.jwt.claim.sub','"+u+"',false)");
 await db.exec("insert into public.invoices(id,company_id,billing_period_end,status)values('"+inv+"','"+c+"',(date_trunc('month',current_date)-interval '1 month')::date+14,'draft')");
 await check("select count(*)::int v from private.invoice_month_end_receipts",0,'OFF receipts empty');
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",true,'OFF keeps legacy approval');
 await db.exec("insert into private.invoice_month_end_rollout values('"+c+"',true)");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'legacy notice is not receipt');
 await reject("select public.approve_invoice('"+inv+"')",'no receipt approval');
 for(const [date,now,want]of [['2026-10-15','2026-10-30T14:59:59Z',false],['2026-10-15','2026-10-30T15:00:00Z',true],['2024-02-15','2024-02-28T15:00:00Z',true],['2025-02-15','2025-02-27T14:59:59Z',false]]){
  await check("select private.invoice_month_end_due('"+date+"','"+now+"') v",want,'JST month-end '+date+' '+now);
 }
 await check("select public.enqueue_due_invoice_approval_notifications() v",1,'first receipt');
 await check("select public.enqueue_due_invoice_approval_notifications() v",0,'dedupe');
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",true,'issued receipt enables');
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u2+"') v",false,'non-approver');
 await check("select public.approve_invoice('"+inv+"') v",true,'approve once');
 await db.exec("select public.cancel_invoice_approval('"+inv+"')");
 await check("select public.enqueue_due_invoice_approval_notifications() v",0,'cancel does not resend');
 await check("select public.approve_invoice('"+inv+"') v",true,'reapprove same receipt');
 await db.exec("update auth.users set banned_until=now()+interval '1 day' where id='"+u+"'");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'banned approver');
 await db.exec("update auth.users set banned_until=null,deleted_at=now() where id='"+u+"'");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'deleted approver');
 await db.exec("update auth.users set deleted_at=null where id='"+u+"'");
 await db.exec("select public.cancel_invoice_approval('"+inv+"'); update public.invoice_approvers set created_at=created_at+interval '1 second' where company_id='"+c+"'");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'registration revision requires notice');
 await check("select public.enqueue_due_invoice_approval_notifications() v",1,'new registration version');
 await db.exec("insert into public.invoices(id,company_id,billing_period_end,status)values('"+inv2+"','"+c+"',(date_trunc('month',current_date)+interval '1 month')::date+14,'draft')");
 await check("select private.invoice_month_end_eligible('"+inv2+"','"+u+"') v",false,'future month blocked');
 await check("select public.enqueue_due_invoice_approval_notifications() v",0,'future month no notice');
 await db.exec("select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false)");
 await check("select public.enqueue_due_invoice_approval_notifications() v",0,'public wrapper other-company scope');
 await db.exec("select set_config('request.jwt.claim.sub','"+u+"',false)");
 await db.exec("delete from public.company_members where company_id='"+c+"' and user_id='"+u+"'");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'removed membership');
 await db.exec("insert into public.company_members values('"+c+"','"+u+"','owner')");
 const inv3='20000000-0000-0000-0000-000000000003';
 await db.exec("insert into public.invoices(id,company_id,billing_period_end,status)values('"+inv3+"','"+c+"',date_trunc('month',current_date)::date-1,'draft')");
 const originalEnqueue=(await db.query("select pg_get_functiondef('private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure) def")).rows[0].def;
 const countBefore=(await db.query("select count(*)::int v from private.invoice_month_end_receipts")).rows[0].v;
 await db.exec("create or replace function private.enqueue_notification(p_company_id uuid,p_recipient_user_id uuid,p_kind text,p_title text,p_body text default null,p_action_key text default null,p_action_id uuid default null)returns uuid language sql as 'select null::uuid'");
 await reject("select public.enqueue_due_invoice_approval_notifications()",'failed enqueue no receipt');
 await check("select count(*)::int v from private.invoice_month_end_receipts",countBefore,'failed enqueue rollback');
 await db.exec(originalEnqueue);
 await check("select public.enqueue_due_invoice_approval_notifications() v",1,'retry after failed enqueue');
 await db.exec("insert into private.account_deletion_access_restrictions values('"+u+"')");
 await check("select private.invoice_month_end_eligible('"+inv+"','"+u+"') v",false,'restricted account');
 await reject("select public.enqueue_due_invoice_approval_notifications()",'restricted caller');
 await db.exec("delete from private.account_deletion_access_restrictions where user_id='"+u+"'");
 for(const role of ['anon','authenticated','service_role']){
  await check("select has_function_privilege('"+role+"','private.run_invoice_month_end_notifications()','execute') v",false,'cron ACL '+role);
  await check("select has_function_privilege('"+role+"','private.dispatch_invoice_month_end_notifications(uuid,uuid)','execute') v",false,'dispatcher ACL '+role);
 }
 await db.exec("select set_config('request.jwt.claim.sub','',false)");
 await check("select private.run_invoice_month_end_notifications() v",0,'owner cron no auth required');
 await reject("select public.enqueue_due_invoice_approval_notifications()",'public requires auth');
 await db.exec("comment on function public.approve_invoice(uuid) is 'fixture';");
 // Changing the body is a real drift; the staged installer must reject it.
 await db.exec("create or replace function public.approve_invoice(p_invoice_id uuid) returns boolean language sql as 'select false'");
 await reject(staged,'drift guard');
 console.log('Invoice month-end gates, receipts, registration versions, ACL and drift assertions passed');
}catch(error){console.error(error.message);process.exitCode=1;}finally{await db.close();}
