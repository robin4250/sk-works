import fs from 'node:fs';
import { createHash } from 'node:crypto';
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
  const fixtureRoot = 'tool/fixtures/viewer_approval_invitation';
  const manifest = JSON.parse(fs.readFileSync(fixtureRoot + '/manifest.json', 'utf8'));
  const scopePath = process.argv[3] ?? fixtureRoot + '/' + manifest.fixture_file;
  const scope = fs.readFileSync(scopePath);
  if (scope.length !== manifest.bytes ||
      createHash('sha256').update(scope).digest('hex') !== manifest.sha256) {
    throw new Error('PR #755 fixture does not match its verbatim source manifest');
  }
  await db.exec(scope.toString('utf8'));
  await db.exec(functionSql('supabase/migrations/20260930062500_fix_manager_vehicle_route_effective_permissions.sql', 'public.current_feature_permissions'));
  await db.exec(`
    alter table workers add column status text, add column role text, add column updated_at timestamptz;
    alter table user_profiles add primary key(user_id), add column phone text, add column updated_at timestamptz;
    alter table app_notifications add column read_at timestamptz;
    create table employee_registration_invites(
      id uuid primary key,company_id uuid,auth_user_id uuid,worker_id uuid,status text,
      requested_role text not null default 'viewer' check(requested_role in ('viewer','manager')),
      requested_approval_assignee boolean not null default false,
      replace_approval_assignee_user_id uuid,name text,phone_e164 text,
      approved_by uuid,approved_at timestamptz,
      constraint employee_registration_invites_requested_approver_role_check
        check(not requested_approval_assignee or requested_role='manager'));
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261009000116_viewer_approval_invitation_role.sql', 'utf8'));
  await db.exec(fs.readFileSync('supabase/tests/viewer_approval_invitation_assertions.sql', 'utf8'));
  console.log('PASS viewer invitation role retention, current-assignee-only approval, replacement/revocation, cross-company/self/blocked denial and no management grant');

} catch (error) { console.error(error.message, error.where ?? ''); process.exitCode = 1; }
finally { await db.close(); }
