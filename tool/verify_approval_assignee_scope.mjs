import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
function functionSql(path, name) {
  const source = fs.readFileSync(path, 'utf8');
  const escaped = name.replaceAll('.', '\\.');
  const match = source.match(new RegExp('create or replace function ' + escaped + '\\([\\s\\S]*?\\n\\$\\$;', 'i'));
  if (!match) throw new Error('missing real function: ' + name);
  return match[0];
}
try {
  await db.exec(`
    create schema auth; create schema private;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
    create function private.account_access_allowed() returns boolean language sql as $$ select coalesce(current_setting('test.blocked',true),'false') <> 'true' $$;
    create table company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
    create table member_feature_permissions(company_id uuid,user_id uuid,
      can_approve_daily_report_edits boolean,can_manage_attendance boolean,can_manage_people boolean,
      can_view_invoices boolean,can_manage_invoices boolean,can_view_admin_site_data boolean,
      can_manage_admin_site_data boolean,can_manage_payroll boolean,can_manage_partner_chat boolean,
      can_manage_vehicles boolean,can_manage_routes boolean,updated_by uuid,updated_at timestamptz,
      primary key(company_id,user_id));
    create table user_profiles(user_id uuid,display_name text);
    create table workers(id uuid primary key,company_id uuid,user_id uuid,name text);
    create table company_approval_assignees(company_id uuid,user_id uuid,created_by uuid,primary key(company_id,user_id));
    create table worker_personnel_approvers(company_id uuid,user_id uuid,position integer check(position between 1 and 3),primary key(company_id,user_id),unique(company_id,position));
    create table daily_report_edit_requests(id uuid primary key,company_id uuid,requested_by uuid,status text,approvals_required integer default 1,resolved_at timestamptz);
    create table daily_report_edit_approvals(request_id uuid,approver_user_id uuid,decision text,decided_at timestamptz default now(),primary key(request_id,approver_user_id));
    create table worker_personnel_change_requests(id uuid primary key,company_id uuid,worker_id uuid,requested_by uuid,proposed jsonb,status text,required_approvals integer,created_at timestamptz default now(),resolved_at timestamptz);
    create table worker_personnel_change_approvals(request_id uuid,approver_user_id uuid,decision text,primary key(request_id,approver_user_id));
    create table app_notifications(company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
    create table applied_payload(worker_id uuid,payload jsonb,actor uuid);
    create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns void language sql as $$ select $$;
    create function private.apply_worker_personnel_payload(uuid,jsonb,uuid) returns void language sql as $$ insert into public.applied_payload values($1,$2,$3) $$;
    alter table daily_report_edit_requests enable row level security;
    alter table daily_report_edit_approvals enable row level security;
    create policy "requester or authorized approver can read edit requests" on daily_report_edit_requests for select to authenticated using(false);
    create policy "requester or authorized approver can read approvals" on daily_report_edit_approvals for select to authenticated using(false);
    grant usage on schema auth,private to authenticated;
    grant select on daily_report_edit_requests,daily_report_edit_approvals to authenticated;
  `);
  const personnel = 'supabase/migrations/20261006192517_worker_personnel_approvers_one_to_three.sql';
  // Exercise live request decision implementations, not simplified replicas.
  await db.exec(functionSql(personnel, 'public.pending_worker_personnel_changes'));
  await db.exec(functionSql(personnel, 'public.decide_worker_personnel_change'));
  await db.exec(fs.readFileSync('supabase/migrations/20261008132016_approval_assignee_viewer_scope.sql', 'utf8'));
  await db.exec(fs.readFileSync('supabase/tests/approval_assignee_scope_assertions.sql', 'utf8'));
  console.log('PASS assigned viewer approval scope, one-to-three configuration, single-person completion, cross-company denial and new-company default');
} catch (error) { console.error(error.message, error.where ?? ''); process.exitCode = 1; }
finally { await db.close(); }
