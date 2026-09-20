create or replace function private.has_company_feature(
  p_company_id uuid,
  p_feature text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_perm public.member_feature_permissions%rowtype;
begin
  if v_user_id is null or p_company_id is null then
    return false;
  end if;

  select cm.role::text
  into v_role
  from public.company_members cm
  where cm.company_id = p_company_id
    and cm.user_id = v_user_id
  limit 1;

  if v_role is null then
    return false;
  end if;

  if v_role in ('owner', 'admin') then
    return true;
  end if;

  select *
  into v_perm
  from public.member_feature_permissions
  where company_id = p_company_id
    and user_id = v_user_id;

  if not found then
    return case
      when v_role = 'manager'
       and p_feature in (
         'can_manage_attendance',
         'can_approve_daily_report_edits'
       )
      then true
      else false
    end;
  end if;

  return case p_feature
    when 'can_view_invoices' then
      v_perm.can_view_invoices or v_perm.can_manage_invoices
    when 'can_manage_invoices' then
      v_perm.can_manage_invoices
    when 'can_view_admin_site_data' then
      v_perm.can_view_admin_site_data or v_perm.can_manage_admin_site_data
    when 'can_manage_admin_site_data' then
      v_perm.can_manage_admin_site_data
    when 'can_manage_payroll' then
      v_perm.can_manage_payroll
    when 'can_manage_people' then
      v_perm.can_manage_people
    when 'can_manage_attendance' then
      v_perm.can_manage_attendance
    when 'can_approve_daily_report_edits' then
      v_perm.can_approve_daily_report_edits
    when 'can_manage_partner_chat' then
      v_perm.can_manage_partner_chat
    else false
  end;
end;
$$;

-- Attendance summaries: a worker sees only their own rows unless they have
-- attendance-management permission.
drop policy if exists "company members can read attendance entries"
  on public.attendance_entries;
drop policy if exists "managers can manage attendance entries"
  on public.attendance_entries;

create policy "worker or attendance manager can read attendance entries"
on public.attendance_entries
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = attendance_entries.worker_id
      and w.company_id = attendance_entries.company_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(
    company_id,
    'can_manage_attendance'
  )
);

create policy "attendance managers can insert attendance entries"
on public.attendance_entries
for insert
to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_attendance')
  and exists (
    select 1 from public.workers w
    where w.id = attendance_entries.worker_id
      and w.company_id = attendance_entries.company_id
  )
  and exists (
    select 1 from public.sites s
    where s.id = attendance_entries.site_id
      and s.company_id = attendance_entries.company_id
  )
);

create policy "attendance managers can update attendance entries"
on public.attendance_entries
for update
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
)
with check (
  private.has_company_feature(company_id, 'can_manage_attendance')
  and exists (
    select 1 from public.workers w
    where w.id = attendance_entries.worker_id
      and w.company_id = attendance_entries.company_id
  )
  and exists (
    select 1 from public.sites s
    where s.id = attendance_entries.site_id
      and s.company_id = attendance_entries.company_id
  )
);

create policy "attendance managers can delete attendance entries"
on public.attendance_entries
for delete
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

-- Everyone needs to read the configured verification mode; only attendance
-- managers may change the company-wide setting.
drop policy if exists "company members can manage attendance verification settings"
  on public.attendance_verification_settings;

create policy "company members can read attendance verification settings"
on public.attendance_verification_settings
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = attendance_verification_settings.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "attendance managers can insert attendance verification settings"
on public.attendance_verification_settings
for insert
to authenticated
with check (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

create policy "attendance managers can update attendance verification settings"
on public.attendance_verification_settings
for update
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
)
with check (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

create policy "attendance managers can delete attendance verification settings"
on public.attendance_verification_settings
for delete
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

-- A worker may create and read only their own clock events. Managers can
-- see all events. Submitted worker events are immutable to the worker.
drop policy if exists "company members can manage attendance verifications"
  on public.attendance_verifications;

create policy "worker or attendance manager can read attendance verifications"
on public.attendance_verifications
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = attendance_verifications.worker_id
      and w.company_id = attendance_verifications.company_id
      and w.user_id = auth.uid()
  )
  or private.has_company_feature(
    company_id,
    'can_manage_attendance'
  )
);

create policy "worker or attendance manager can create verification"
on public.attendance_verifications
for insert
to authenticated
with check (
  (
    exists (
      select 1
      from public.workers w
      where w.id = attendance_verifications.worker_id
        and w.company_id = attendance_verifications.company_id
        and w.user_id = auth.uid()
    )
    or private.has_company_feature(
      company_id,
      'can_manage_attendance'
    )
  )
  and exists (
    select 1 from public.sites s
    where s.id = attendance_verifications.site_id
      and s.company_id = attendance_verifications.company_id
  )
);

create policy "attendance managers can update verifications"
on public.attendance_verifications
for update
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
)
with check (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

create policy "attendance managers can delete verifications"
on public.attendance_verifications
for delete
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_attendance')
);

-- Daily-report correction requests honor the explicit approval toggle.
drop policy if exists "members can read own report edit requests"
  on public.daily_report_edit_requests;

create policy "requester or authorized approver can read edit requests"
on public.daily_report_edit_requests
for select
to authenticated
using (
  requested_by = auth.uid()
  or private.has_company_feature(
    company_id,
    'can_approve_daily_report_edits'
  )
);

drop policy if exists "members can read report edit approvals"
  on public.daily_report_edit_approvals;

create policy "requester or authorized approver can read approvals"
on public.daily_report_edit_approvals
for select
to authenticated
using (
  exists (
    select 1
    from public.daily_report_edit_requests req
    where req.id = daily_report_edit_approvals.request_id
      and (
        req.requested_by = auth.uid()
        or private.has_company_feature(
          req.company_id,
          'can_approve_daily_report_edits'
        )
      )
  )
);

create or replace function public.request_daily_report_edit(
  p_report_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_request_id uuid;
  v_approver record;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select dr.company_id
  into v_company_id
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id = dr.company_id
   and cm.user_id = v_user_id
  where dr.id = p_report_id
    and dr.status = 'signed';

  if v_company_id is null then
    raise exception 'signed daily report not found';
  end if;

  insert into public.daily_report_edit_requests(
    report_id,
    company_id,
    requested_by,
    reason
  )
  values(
    p_report_id,
    v_company_id,
    v_user_id,
    nullif(trim(coalesce(p_reason, '')), '')
  )
  returning id into v_request_id;

  for v_approver in
    select cm.user_id
    from public.company_members cm
    left join public.member_feature_permissions mfp
      on mfp.company_id = cm.company_id
     and mfp.user_id = cm.user_id
    where cm.company_id = v_company_id
      and cm.user_id <> v_user_id
      and (
        cm.role::text in ('owner', 'admin')
        or (
          cm.role::text = 'manager'
          and coalesce(
            mfp.can_approve_daily_report_edits,
            true
          )
        )
        or coalesce(
          mfp.can_approve_daily_report_edits,
          false
        )
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      v_approver.user_id,
      'approval',
      '日報の修正承認',
      '確定済み日報の修正申請があります。',
      'daily_report_edit_request',
      v_request_id
    );
  end loop;

  return v_request_id;
end;
$$;

create or replace function public.decide_daily_report_edit(
  p_request_id uuid,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_required integer;
  v_approve_count integer;
  v_status text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select req.company_id, req.requested_by, req.approvals_required, req.status
  into v_company_id, v_requested_by, v_required, v_status
  from public.daily_report_edit_requests req
  where req.id = p_request_id
  for update;

  if v_company_id is null or v_status <> 'pending' then
    raise exception 'pending request not found';
  end if;

  if not private.has_company_feature(
    v_company_id,
    'can_approve_daily_report_edits'
  ) then
    raise exception 'approval permission required';
  end if;

  if v_requested_by = v_user_id then
    raise exception 'requester cannot approve own request';
  end if;

  insert into public.daily_report_edit_approvals(
    request_id,
    approver_user_id,
    decision
  )
  values(
    p_request_id,
    v_user_id,
    p_decision
  )
  on conflict(request_id, approver_user_id) do update
  set decision = excluded.decision,
      decided_at = now();

  if p_decision = 'reject' then
    update public.daily_report_edit_requests
    set status = 'rejected',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'warning',
      '日報修正申請が却下されました',
      '確定済み日報の修正申請が却下されました。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'rejected';
  end if;

  select count(*)
  into v_approve_count
  from public.daily_report_edit_approvals
  where request_id = p_request_id
    and decision = 'approve';

  if v_approve_count >= v_required then
    update public.daily_report_edit_requests
    set status = 'approved',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'approval',
      '日報を編集できます',
      '2名の承認が完了しました。日報を開いて編集してください。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'approved';
  end if;

  return 'pending';
end;
$$;
