alter table public.member_feature_permissions
  add column if not exists can_view_payroll_adjustments boolean not null default false,
  add column if not exists can_manage_payroll_adjustments boolean not null default false;

create or replace function public.can_view_payroll_adjustments(p_company_id uuid)
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
      and cm.role::text in ('owner','admin')
  )
  or exists (
    select 1
    from public.member_feature_permissions p
    where p.company_id = p_company_id
      and p.user_id = auth.uid()
      and (
        p.can_view_payroll_adjustments
        or p.can_manage_payroll_adjustments
      )
  );
$$;

create or replace function public.can_manage_payroll_adjustments(p_company_id uuid)
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
      and cm.role::text in ('owner','admin')
  )
  or exists (
    select 1
    from public.member_feature_permissions p
    where p.company_id = p_company_id
      and p.user_id = auth.uid()
      and p.can_manage_payroll_adjustments
  );
$$;

revoke execute on function public.can_view_payroll_adjustments(uuid)
  from public, anon;
revoke execute on function public.can_manage_payroll_adjustments(uuid)
  from public, anon;
grant execute on function public.can_view_payroll_adjustments(uuid)
  to authenticated;
grant execute on function public.can_manage_payroll_adjustments(uuid)
  to authenticated;

create table if not exists public.company_payroll_adjustment_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  page_label text not null default '給与調整',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint company_payroll_adjustment_settings_label_nonempty
    check (length(btrim(page_label)) > 0)
);

create table if not exists public.payroll_adjustment_types (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  label text not null,
  direction text not null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_adjustment_types_label_nonempty
    check (length(btrim(label)) > 0),
  constraint payroll_adjustment_types_direction
    check (direction in ('addition','deduction')),
  unique(company_id, label)
);

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  type_id uuid references public.payroll_adjustment_types(id) on delete set null,
  label_snapshot text not null,
  direction text not null,
  amount_yen integer not null,
  effective_date date not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint payroll_adjustments_label_nonempty
    check (length(btrim(label_snapshot)) > 0),
  constraint payroll_adjustments_direction
    check (direction in ('addition','deduction')),
  constraint payroll_adjustments_amount_nonnegative
    check (amount_yen >= 0)
);

create index if not exists payroll_adjustments_company_worker_date_idx
  on public.payroll_adjustments(company_id, worker_id, effective_date desc);
create index if not exists payroll_adjustment_types_company_active_idx
  on public.payroll_adjustment_types(company_id, is_active, label);

alter table public.company_payroll_adjustment_settings enable row level security;
alter table public.payroll_adjustment_types enable row level security;
alter table public.payroll_adjustments enable row level security;

drop policy if exists "authorized users read payroll adjustment settings"
  on public.company_payroll_adjustment_settings;
create policy "authorized users read payroll adjustment settings"
on public.company_payroll_adjustment_settings
for select
to authenticated
using (public.can_view_payroll_adjustments(company_id));

drop policy if exists "full admins manage payroll adjustment settings"
  on public.company_payroll_adjustment_settings;
create policy "full admins manage payroll adjustment settings"
on public.company_payroll_adjustment_settings
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_payroll_adjustment_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_payroll_adjustment_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

drop policy if exists "authorized users read payroll adjustment types"
  on public.payroll_adjustment_types;
create policy "authorized users read payroll adjustment types"
on public.payroll_adjustment_types
for select
to authenticated
using (public.can_view_payroll_adjustments(company_id));

drop policy if exists "authorized managers manage payroll adjustment types"
  on public.payroll_adjustment_types;
create policy "authorized managers manage payroll adjustment types"
on public.payroll_adjustment_types
for all
to authenticated
using (public.can_manage_payroll_adjustments(company_id))
with check (public.can_manage_payroll_adjustments(company_id));

drop policy if exists "authorized users read payroll adjustments"
  on public.payroll_adjustments;
create policy "authorized users read payroll adjustments"
on public.payroll_adjustments
for select
to authenticated
using (public.can_view_payroll_adjustments(company_id));

drop policy if exists "authorized managers manage payroll adjustments"
  on public.payroll_adjustments;
create policy "authorized managers manage payroll adjustments"
on public.payroll_adjustments
for insert
to authenticated
with check (public.can_manage_payroll_adjustments(company_id));

drop policy if exists "authorized managers update payroll adjustments"
  on public.payroll_adjustments;
create policy "authorized managers update payroll adjustments"
on public.payroll_adjustments
for update
to authenticated
using (public.can_manage_payroll_adjustments(company_id))
with check (public.can_manage_payroll_adjustments(company_id));

create or replace function public.current_payroll_adjustment_permissions()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with membership as (
    select cm.company_id, cm.role::text as role
    from public.company_members cm
    where cm.user_id = auth.uid()
    limit 1
  )
  select case
    when m.company_id is null then '{}'::jsonb
    when m.role in ('owner','admin') then jsonb_build_object(
      'can_view', true,
      'can_manage', true,
      'can_rename_page', true
    )
    else jsonb_build_object(
      'can_view', coalesce(p.can_view_payroll_adjustments, false)
        or coalesce(p.can_manage_payroll_adjustments, false),
      'can_manage', coalesce(p.can_manage_payroll_adjustments, false),
      'can_rename_page', false
    )
  end
  from membership m
  left join public.member_feature_permissions p
    on p.company_id = m.company_id
   and p.user_id = auth.uid()
  union all
  select '{}'::jsonb
  where not exists (select 1 from membership)
  limit 1;
$$;

create or replace function public.set_payroll_adjustment_permissions(
  p_user_id uuid,
  p_can_view boolean,
  p_can_manage boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = p_user_id
  ) then
    raise exception 'target user is not in company';
  end if;

  insert into public.member_feature_permissions(
    company_id,
    user_id,
    can_view_payroll_adjustments,
    can_manage_payroll_adjustments,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_user_id,
    p_can_view or p_can_manage,
    p_can_manage,
    v_actor,
    now()
  )
  on conflict(company_id, user_id) do update
  set can_view_payroll_adjustments =
        excluded.can_view_payroll_adjustments,
      can_manage_payroll_adjustments =
        excluded.can_manage_payroll_adjustments,
      updated_by = v_actor,
      updated_at = now();
end;
$$;

revoke execute on function public.current_payroll_adjustment_permissions()
  from public, anon;
revoke execute on function public.set_payroll_adjustment_permissions(uuid,boolean,boolean)
  from public, anon;
grant execute on function public.current_payroll_adjustment_permissions()
  to authenticated;
grant execute on function public.set_payroll_adjustment_permissions(uuid,boolean,boolean)
  to authenticated;
