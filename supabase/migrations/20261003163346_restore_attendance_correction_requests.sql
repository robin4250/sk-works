create table if not exists public.attendance_correction_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'draft'
    check (status in ('draft','submitted','approved','rejected','cancelled')),
  signer_name text,
  signature_json jsonb,
  signed_at timestamptz,
  submitted_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_correction_signature_consistency
    check (
      (signed_at is null and signer_name is null and signature_json is null)
      or
      (signed_at is not null and signer_name is not null and signature_json is not null)
    )
);

create table if not exists public.attendance_correction_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.attendance_correction_requests(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  attendance_entry_id uuid not null
    references public.attendance_entries(id) on delete restrict,
  original_snapshot jsonb not null,
  proposed_snapshot jsonb not null,
  change_summary text,
  created_at timestamptz not null default now()
);

create index if not exists attendance_correction_requests_company_status_idx
  on public.attendance_correction_requests(company_id, status, created_at desc);

create index if not exists attendance_correction_items_request_idx
  on public.attendance_correction_items(request_id, created_at);

create index if not exists attendance_correction_items_entry_idx
  on public.attendance_correction_items(attendance_entry_id);

alter table public.attendance_correction_requests enable row level security;
alter table public.attendance_correction_items enable row level security;

create or replace function public.can_manage_attendance_corrections(
  p_company_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.company_members cm
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and (
        cm.role::text in ('owner','admin')
        or (
          cm.role::text = 'manager'
          and coalesce(
            (
              select (public.current_feature_permissions()
                ->> 'can_manage_attendance')::boolean
            ),
            false
          )
        )
      )
  );
$$;

drop policy if exists "attendance managers read correction requests"
  on public.attendance_correction_requests;
create policy "attendance managers read correction requests"
on public.attendance_correction_requests
for select
to authenticated
using (public.can_manage_attendance_corrections(company_id));

drop policy if exists "attendance managers create correction requests"
  on public.attendance_correction_requests;
create policy "attendance managers create correction requests"
on public.attendance_correction_requests
for insert
to authenticated
with check (
  requested_by = auth.uid()
  and public.can_manage_attendance_corrections(company_id)
);

drop policy if exists "attendance managers update own draft correction requests"
  on public.attendance_correction_requests;
create policy "attendance managers update own draft correction requests"
on public.attendance_correction_requests
for update
to authenticated
using (
  requested_by = auth.uid()
  and status = 'draft'
  and public.can_manage_attendance_corrections(company_id)
)
with check (
  requested_by = auth.uid()
  and status in ('draft','submitted','cancelled')
  and public.can_manage_attendance_corrections(company_id)
);

drop policy if exists "attendance managers read correction items"
  on public.attendance_correction_items;
create policy "attendance managers read correction items"
on public.attendance_correction_items
for select
to authenticated
using (public.can_manage_attendance_corrections(company_id));

drop policy if exists "attendance managers create correction items"
  on public.attendance_correction_items;
create policy "attendance managers create correction items"
on public.attendance_correction_items
for insert
to authenticated
with check (
  public.can_manage_attendance_corrections(company_id)
  and exists (
    select 1
    from public.attendance_correction_requests r
    where r.id = request_id
      and r.company_id = attendance_correction_items.company_id
      and r.requested_by = auth.uid()
      and r.status = 'draft'
  )
);

drop policy if exists "attendance managers update correction items"
  on public.attendance_correction_items;
create policy "attendance managers update correction items"
on public.attendance_correction_items
for update
to authenticated
using (
  public.can_manage_attendance_corrections(company_id)
  and exists (
    select 1
    from public.attendance_correction_requests r
    where r.id = request_id
      and r.requested_by = auth.uid()
      and r.status = 'draft'
  )
)
with check (
  public.can_manage_attendance_corrections(company_id)
  and exists (
    select 1
    from public.attendance_correction_requests r
    where r.id = request_id
      and r.requested_by = auth.uid()
      and r.status = 'draft'
  )
);

drop policy if exists "attendance managers delete correction items"
  on public.attendance_correction_items;
create policy "attendance managers delete correction items"
on public.attendance_correction_items
for delete
to authenticated
using (
  public.can_manage_attendance_corrections(company_id)
  and exists (
    select 1
    from public.attendance_correction_requests r
    where r.id = request_id
      and r.requested_by = auth.uid()
      and r.status = 'draft'
  )
);

create or replace function public.submit_attendance_correction_request(
  p_request_id uuid,
  p_signer_name text,
  p_signature_json jsonb
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_request public.attendance_correction_requests%rowtype;
  v_assignee record;
  v_assignee_count integer;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  select *
  into v_request
  from public.attendance_correction_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'attendance correction request not found';
  end if;

  if v_request.requested_by <> v_actor or v_request.status <> 'draft' then
    raise exception 'only the draft owner can submit this request';
  end if;

  if not public.can_manage_attendance_corrections(v_request.company_id) then
    raise exception 'attendance correction permission required';
  end if;

  if trim(coalesce(p_signer_name, '')) = '' or p_signature_json is null then
    raise exception 'signature is required';
  end if;

  if not exists (
    select 1
    from public.attendance_correction_items i
    where i.request_id = p_request_id
  ) then
    raise exception 'at least one correction item is required';
  end if;

  select count(*)
  into v_assignee_count
  from public.company_approval_assignees
  where company_id = v_request.company_id;

  if v_assignee_count < 1 or v_assignee_count > 3 then
    raise exception 'company approval assignee configuration is invalid';
  end if;

  update public.attendance_correction_requests
  set status = 'submitted',
      signer_name = trim(p_signer_name),
      signature_json = p_signature_json,
      signed_at = now(),
      submitted_at = now(),
      updated_at = now()
  where id = p_request_id;

  for v_assignee in
    select caa.user_id
    from public.company_approval_assignees caa
    where caa.company_id = v_request.company_id
  loop
    perform private.enqueue_notification(
      v_request.company_id,
      v_assignee.user_id,
      'approval',
      '過去勤怠のまとめて修正',
      '過去勤怠のまとめて修正申請があります。',
      'attendance_correction_request',
      p_request_id
    );
  end loop;
end;
$$;

create or replace function public.pending_attendance_correction_rows()
returns table(
  request_id uuid,
  requested_by uuid,
  requested_by_name text,
  item_count bigint,
  signer_name text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select caa.company_id
  into v_company_id
  from public.company_approval_assignees caa
  where caa.user_id = v_actor
  limit 1;

  if v_company_id is null then
    raise exception 'approval assignee permission required';
  end if;

  return query
  select
    r.id,
    r.requested_by,
    coalesce(up.display_name, 'SKOユーザー'),
    count(i.id),
    r.signer_name,
    r.submitted_at
  from public.attendance_correction_requests r
  left join public.attendance_correction_items i
    on i.request_id = r.id
  left join public.user_profiles up
    on up.user_id = r.requested_by
  where r.company_id = v_company_id
    and r.status = 'submitted'
  group by
    r.id,
    r.requested_by,
    up.display_name,
    r.signer_name,
    r.submitted_at
  order by r.submitted_at;
end;
$$;

create or replace function public.attendance_correction_item_rows(
  p_request_id uuid
)
returns table(
  item_id uuid,
  attendance_entry_id uuid,
  original_snapshot jsonb,
  proposed_snapshot jsonb,
  change_summary text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select caa.company_id
  into v_company_id
  from public.company_approval_assignees caa
  where caa.user_id = v_actor
  limit 1;

  if v_company_id is null then
    raise exception 'approval assignee permission required';
  end if;

  if not exists (
    select 1
    from public.attendance_correction_requests r
    where r.id = p_request_id
      and r.company_id = v_company_id
      and r.status = 'submitted'
  ) then
    raise exception 'submitted attendance correction request not found';
  end if;

  return query
  select
    i.id,
    i.attendance_entry_id,
    i.original_snapshot,
    i.proposed_snapshot,
    i.change_summary
  from public.attendance_correction_items i
  where i.request_id = p_request_id
    and i.company_id = v_company_id
  order by i.created_at;
end;
$$;

create or replace function public.decide_attendance_correction_request(
  p_request_id uuid,
  p_decision text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_request public.attendance_correction_requests%rowtype;
  v_assignee_count integer;
  v_item record;
  v_site_id uuid;
begin
  if v_actor is null then
    raise exception 'authentication required';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select *
  into v_request
  from public.attendance_correction_requests
  where id = p_request_id
  for update;

  if not found or v_request.status <> 'submitted' then
    raise exception 'submitted attendance correction request not found';
  end if;

  if not exists (
    select 1
    from public.company_approval_assignees caa
    where caa.company_id = v_request.company_id
      and caa.user_id = v_actor
  ) then
    raise exception 'approval assignee permission required';
  end if;

  select count(*)
  into v_assignee_count
  from public.company_approval_assignees
  where company_id = v_request.company_id;

  if v_request.requested_by = v_actor and v_assignee_count > 1 then
    raise exception 'requester cannot approve own request';
  end if;

  if p_decision = 'reject' then
    update public.attendance_correction_requests
    set status = 'rejected',
        reviewed_by = v_actor,
        reviewed_at = now(),
        review_note = nullif(trim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_request.company_id,
      v_request.requested_by,
      'warning',
      '過去勤怠の修正申請が却下されました',
      'まとめて修正申請が却下されました。内容を確認してください。',
      'attendance_correction_request',
      p_request_id
    );

    return 'rejected';
  end if;

  for v_item in
    select *
    from public.attendance_correction_items
    where request_id = p_request_id
      and company_id = v_request.company_id
    order by created_at
  loop
    select s.id
    into v_site_id
    from public.sites s
    where s.company_id = v_request.company_id
      and s.name = trim(coalesce(v_item.proposed_snapshot ->> 'siteName', ''))
    limit 2;

    if v_site_id is null then
      raise exception 'site not found for correction item';
    end if;

    if (
      select count(*)
      from public.sites s
      where s.company_id = v_request.company_id
        and s.name = trim(coalesce(v_item.proposed_snapshot ->> 'siteName', ''))
    ) > 1 then
      raise exception 'duplicate site name for correction item';
    end if;

    update public.attendance_entries
    set site_id = v_site_id,
        base_man_days = coalesce(
          (v_item.proposed_snapshot ->> 'manDays')::numeric,
          base_man_days
        ),
        overtime_hours = coalesce(
          (v_item.proposed_snapshot ->> 'overtimeHours')::numeric,
          overtime_hours
        ),
        early_hours = coalesce(
          (v_item.proposed_snapshot ->> 'earlyHours')::numeric,
          early_hours
        ),
        night_hours = coalesce(
          (v_item.proposed_snapshot ->> 'nightHours')::numeric,
          night_hours
        ),
        allowance_amount = coalesce(
          (v_item.proposed_snapshot ->> 'allowanceYen')::integer,
          allowance_amount
        ),
        notes = nullif(
          trim(coalesce(v_item.proposed_snapshot ->> 'notes', '')),
          ''
        ),
        updated_by = v_actor,
        updated_at = now()
    where id = v_item.attendance_entry_id
      and company_id = v_request.company_id;
  end loop;

  update public.attendance_correction_requests
  set status = 'approved',
      reviewed_by = v_actor,
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note, '')), ''),
      updated_at = now()
  where id = p_request_id;

  perform private.enqueue_notification(
    v_request.company_id,
    v_request.requested_by,
    'approval',
    '過去勤怠の修正が反映されました',
    'まとめて修正申請が承認され、勤怠へ反映されました。',
    'attendance_correction_request',
    p_request_id
  );

  return 'approved';
end;
$$;

revoke execute on function public.can_manage_attendance_corrections(uuid)
  from public, anon;
revoke execute on function public.submit_attendance_correction_request(uuid,text,jsonb)
  from public, anon;
revoke execute on function public.pending_attendance_correction_rows()
  from public, anon;
revoke execute on function public.attendance_correction_item_rows(uuid)
  from public, anon;
revoke execute on function public.decide_attendance_correction_request(uuid,text,text)
  from public, anon;

grant execute on function public.can_manage_attendance_corrections(uuid)
  to authenticated;
grant execute on function public.submit_attendance_correction_request(uuid,text,jsonb)
  to authenticated;
grant execute on function public.pending_attendance_correction_rows()
  to authenticated;
grant execute on function public.attendance_correction_item_rows(uuid)
  to authenticated;
grant execute on function public.decide_attendance_correction_request(uuid,text,text)
  to authenticated;


-- Production restore on 2026-10-04: explicit Data API grants.
-- RLS policies above continue to restrict actual row access.
grant select, insert, update, delete
  on public.attendance_correction_requests
  to authenticated;
grant select, insert, update, delete
  on public.attendance_correction_items
  to authenticated;
