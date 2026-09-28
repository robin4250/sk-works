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
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_request public.attendance_correction_requests%rowtype;
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

  update public.attendance_correction_requests
  set status = 'submitted',
      signer_name = trim(p_signer_name),
      signature_json = p_signature_json,
      signed_at = now(),
      submitted_at = now(),
      updated_at = now()
  where id = p_request_id;
end;
$$;

revoke execute on function public.can_manage_attendance_corrections(uuid)
  from public, anon;
revoke execute on function public.submit_attendance_correction_request(uuid,text,jsonb)
  from public, anon;

grant execute on function public.can_manage_attendance_corrections(uuid)
  to authenticated;
grant execute on function public.submit_attendance_correction_request(uuid,text,jsonb)
  to authenticated;
