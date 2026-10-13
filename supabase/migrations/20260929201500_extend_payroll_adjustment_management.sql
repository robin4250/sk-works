alter table public.payroll_adjustments
  add column if not exists cancellation_reason text;

create table if not exists public.payroll_adjustment_audit_log (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  action text not null,
  target_kind text not null,
  target_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payroll_adjustment_audit_company_created_idx
  on public.payroll_adjustment_audit_log(company_id, created_at desc);

alter table public.payroll_adjustment_audit_log enable row level security;

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
    from public.company_members cm
    join public.member_feature_permissions p
      on p.company_id = cm.company_id
     and p.user_id = cm.user_id
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('manager','viewer')
      and (
        p.can_view_payroll_adjustments
        or (
          cm.role::text = 'manager'
          and p.can_manage_payroll_adjustments
        )
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
    from public.company_members cm
    join public.member_feature_permissions p
      on p.company_id = cm.company_id
     and p.user_id = cm.user_id
    where cm.company_id = p_company_id
      and cm.user_id = auth.uid()
      and cm.role::text = 'manager'
      and p.can_manage_payroll_adjustments
  );
$$;

create or replace function public.current_payroll_adjustment_permissions()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company_id uuid;
  v_role text;
  v_page_label text := '給与調整';
  v_can_view boolean := false;
  v_can_manage boolean := false;
begin
  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    return jsonb_build_object(
      'can_view', false,
      'can_manage', false,
      'can_rename_page', false,
      'page_label', v_page_label
    );
  end if;

  v_can_view := public.can_view_payroll_adjustments(v_company_id);
  v_can_manage := public.can_manage_payroll_adjustments(v_company_id);

  select coalesce(s.page_label, '給与調整')
  into v_page_label
  from (
    select v_company_id as company_id
  ) x
  left join public.company_payroll_adjustment_settings s
    on s.company_id = x.company_id;

  return jsonb_build_object(
    'company_id', v_company_id,
    'role', v_role,
    'can_view', v_can_view,
    'can_manage', v_can_manage,
    'can_rename_page', v_role in ('owner','admin'),
    'page_label', coalesce(v_page_label, '給与調整')
  );
end;
$$;

create or replace function public.payroll_adjustment_access()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'company_id', p ->> 'company_id',
    'role', p ->> 'role',
    'page_label', coalesce(p ->> 'page_label', '給与調整'),
    'can_view', coalesce((p ->> 'can_view')::boolean, false),
    'can_manage', coalesce((p ->> 'can_manage')::boolean, false),
    'can_rename', coalesce((p ->> 'can_rename_page')::boolean, false)
  )
  from (
    select public.current_payroll_adjustment_permissions() as p
  ) q;
$$;

create or replace function public.company_payroll_adjustment_permission_rows()
returns table(
  user_id uuid,
  can_view boolean,
  can_manage boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = auth.uid()
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  return query
  select
    cm.user_id,
    case
      when cm.role::text in ('owner','admin') then true
      else coalesce(p.can_view_payroll_adjustments, false)
        or (
          cm.role::text = 'manager'
          and coalesce(p.can_manage_payroll_adjustments, false)
        )
    end,
    case
      when cm.role::text in ('owner','admin') then true
      when cm.role::text = 'manager'
        then coalesce(p.can_manage_payroll_adjustments, false)
      else false
    end
  from public.company_members cm
  left join public.member_feature_permissions p
    on p.company_id = cm.company_id
   and p.user_id = cm.user_id
  where cm.company_id = v_company_id
  order by cm.user_id;
end;
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
  v_target_role text;
  v_view boolean;
  v_manage boolean;
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

  select cm.role::text
  into v_target_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = p_user_id
  limit 1;

  if v_target_role is null then
    raise exception 'target user is not in company';
  end if;

  if v_target_role in ('owner','admin') then
    return;
  end if;

  v_manage :=
    v_target_role = 'manager'
    and coalesce(p_can_manage, false);
  v_view :=
    coalesce(p_can_view, false)
    or v_manage;

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
    v_view,
    v_manage,
    v_actor,
    now()
  )
  on conflict(company_id,user_id) do update
  set can_view_payroll_adjustments =
        excluded.can_view_payroll_adjustments,
      can_manage_payroll_adjustments =
        excluded.can_manage_payroll_adjustments,
      updated_by = v_actor,
      updated_at = now();

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'permission_change',
    'user',
    p_user_id,
    v_actor,
    jsonb_build_object(
      'role', v_target_role,
      'can_view', v_view,
      'can_manage', v_manage
    )
  );
end;
$$;

create or replace function public.set_payroll_adjustment_page_label(
  p_label text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_label text := trim(coalesce(p_label, ''));
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

  if char_length(v_label) < 1 or char_length(v_label) > 40 then
    raise exception 'page label must be 1 to 40 characters';
  end if;

  insert into public.company_payroll_adjustment_settings(
    company_id,
    page_label,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    v_label,
    v_actor,
    now()
  )
  on conflict(company_id) do update
  set page_label = excluded.page_label,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'page_label_change',
    'settings',
    v_actor,
    jsonb_build_object('page_label', v_label)
  );
end;
$$;

create or replace function public.payroll_adjustment_worker_rows()
returns table(
  worker_id uuid,
  worker_name text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
begin
  if coalesce((v_access ->> 'can_view')::boolean, false) is not true then
    raise exception 'payroll adjustment view permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  return query
  select w.id, w.name
  from public.workers w
  where w.company_id = v_company_id
    and w.status = 'active'
  order by w.name;
end;
$$;

create or replace function public.payroll_adjustment_type_rows()
returns table(
  id uuid,
  label text,
  direction text,
  is_active boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
begin
  if coalesce((v_access ->> 'can_view')::boolean, false) is not true then
    raise exception 'payroll adjustment view permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  return query
  select t.id, t.label, t.direction, t.is_active
  from public.payroll_adjustment_types t
  where t.company_id = v_company_id
  order by t.is_active desc, t.label;
end;
$$;

create or replace function public.payroll_adjustment_rows(
  p_worker_id uuid default null,
  p_start date default null,
  p_end date default null
)
returns table(
  id uuid,
  worker_id uuid,
  worker_name text,
  type_id uuid,
  label text,
  direction text,
  amount_yen integer,
  effective_date date,
  note text,
  created_by uuid,
  created_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid,
  cancellation_reason text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
begin
  if coalesce((v_access ->> 'can_view')::boolean, false) is not true then
    raise exception 'payroll adjustment view permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  return query
  select
    a.id,
    a.worker_id,
    w.name,
    a.type_id,
    a.label_snapshot,
    a.direction,
    a.amount_yen,
    a.effective_date,
    a.note,
    a.created_by,
    a.created_at,
    a.cancelled_at,
    a.cancelled_by,
    a.cancellation_reason
  from public.payroll_adjustments a
  join public.workers w
    on w.id = a.worker_id
   and w.company_id = a.company_id
  where a.company_id = v_company_id
    and (p_worker_id is null or a.worker_id = p_worker_id)
    and (p_start is null or a.effective_date >= p_start)
    and (p_end is null or a.effective_date <= p_end)
  order by a.effective_date desc, a.created_at desc;
end;
$$;

create or replace function public.upsert_payroll_adjustment_type(
  p_id uuid,
  p_label text,
  p_direction text,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_id uuid;
  v_label text := trim(coalesce(p_label, ''));
  v_direction text := trim(coalesce(p_direction, ''));
  v_action text;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  if char_length(v_label) < 1 or char_length(v_label) > 60 then
    raise exception 'adjustment label must be 1 to 60 characters';
  end if;

  if v_direction not in ('addition','deduction') then
    raise exception 'invalid adjustment direction';
  end if;

  if p_id is null then
    insert into public.payroll_adjustment_types(
      company_id,
      label,
      direction,
      is_active,
      created_by
    )
    values(
      v_company_id,
      v_label,
      v_direction,
      p_is_active,
      v_actor
    )
    returning id into v_id;
    v_action := 'type_create';
  else
    update public.payroll_adjustment_types
    set label = v_label,
        direction = v_direction,
        is_active = p_is_active,
        updated_at = now()
    where id = p_id
      and company_id = v_company_id
    returning id into v_id;

    if v_id is null then
      raise exception 'payroll adjustment type not found';
    end if;

    v_action := 'type_update';
  end if;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    v_action,
    'type',
    v_id,
    v_actor,
    jsonb_build_object(
      'label', v_label,
      'direction', v_direction,
      'is_active', p_is_active
    )
  );

  return v_id;
end;
$$;

create or replace function public.create_payroll_adjustment(
  p_worker_id uuid,
  p_type_id uuid,
  p_amount_yen integer,
  p_effective_date date,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_label text;
  v_direction text;
  v_id uuid;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  if p_amount_yen is null or p_amount_yen <= 0 then
    raise exception 'amount must be greater than zero';
  end if;

  if p_effective_date is null then
    raise exception 'effective date is required';
  end if;

  if not exists (
    select 1
    from public.workers w
    where w.id = p_worker_id
      and w.company_id = v_company_id
      and w.status = 'active'
  ) then
    raise exception 'worker not found';
  end if;

  select t.label, t.direction
  into v_label, v_direction
  from public.payroll_adjustment_types t
  where t.id = p_type_id
    and t.company_id = v_company_id
    and t.is_active = true;

  if v_label is null then
    raise exception 'active payroll adjustment type not found';
  end if;

  insert into public.payroll_adjustments(
    company_id,
    worker_id,
    type_id,
    label_snapshot,
    direction,
    amount_yen,
    effective_date,
    note,
    created_by
  )
  values(
    v_company_id,
    p_worker_id,
    p_type_id,
    v_label,
    v_direction,
    p_amount_yen,
    p_effective_date,
    nullif(trim(coalesce(p_note, '')), ''),
    v_actor
  )
  returning id into v_id;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'adjustment_create',
    'adjustment',
    v_id,
    v_actor,
    jsonb_build_object(
      'worker_id', p_worker_id,
      'type_id', p_type_id,
      'label', v_label,
      'direction', v_direction,
      'amount_yen', p_amount_yen,
      'effective_date', p_effective_date
    )
  );

  return v_id;
end;
$$;

create or replace function public.cancel_payroll_adjustment(
  p_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_row public.payroll_adjustments%rowtype;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  select *
  into v_row
  from public.payroll_adjustments
  where id = p_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'payroll adjustment not found';
  end if;

  if v_row.cancelled_at is not null then
    return;
  end if;

  update public.payroll_adjustments
  set cancelled_at = now(),
      cancelled_by = v_actor,
      cancellation_reason =
        nullif(trim(coalesce(p_reason, '')), ''),
      updated_at = now()
  where id = p_id
    and company_id = v_company_id;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'adjustment_cancel',
    'adjustment',
    p_id,
    v_actor,
    jsonb_build_object(
      'worker_id', v_row.worker_id,
      'label', v_row.label_snapshot,
      'direction', v_row.direction,
      'amount_yen', v_row.amount_yen,
      'effective_date', v_row.effective_date,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );
end;
$$;

drop policy if exists "full admins manage payroll adjustment settings"
  on public.company_payroll_adjustment_settings;
drop policy if exists "authorized managers manage payroll adjustment types"
  on public.payroll_adjustment_types;
drop policy if exists "authorized managers manage payroll adjustments"
  on public.payroll_adjustments;
drop policy if exists "authorized managers update payroll adjustments"
  on public.payroll_adjustments;

drop policy if exists "admins read payroll adjustment audit"
  on public.payroll_adjustment_audit_log;
create policy "admins read payroll adjustment audit"
on public.payroll_adjustment_audit_log
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = payroll_adjustment_audit_log.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

revoke execute on function public.can_view_payroll_adjustments(uuid)
  from public, anon;
revoke execute on function public.can_manage_payroll_adjustments(uuid)
  from public, anon;
revoke execute on function public.current_payroll_adjustment_permissions()
  from public, anon;
revoke execute on function public.payroll_adjustment_access()
  from public, anon;
revoke execute on function public.company_payroll_adjustment_permission_rows()
  from public, anon;
revoke execute on function public.set_payroll_adjustment_permissions(uuid,boolean,boolean)
  from public, anon;
revoke execute on function public.set_payroll_adjustment_page_label(text)
  from public, anon;
revoke execute on function public.payroll_adjustment_worker_rows()
  from public, anon;
revoke execute on function public.payroll_adjustment_type_rows()
  from public, anon;
revoke execute on function public.payroll_adjustment_rows(uuid,date,date)
  from public, anon;
revoke execute on function public.upsert_payroll_adjustment_type(uuid,text,text,boolean)
  from public, anon;
revoke execute on function public.create_payroll_adjustment(uuid,uuid,integer,date,text)
  from public, anon;
revoke execute on function public.cancel_payroll_adjustment(uuid,text)
  from public, anon;

grant execute on function public.can_view_payroll_adjustments(uuid)
  to authenticated;
grant execute on function public.can_manage_payroll_adjustments(uuid)
  to authenticated;
grant execute on function public.current_payroll_adjustment_permissions()
  to authenticated;
grant execute on function public.payroll_adjustment_access()
  to authenticated;
grant execute on function public.company_payroll_adjustment_permission_rows()
  to authenticated;
grant execute on function public.set_payroll_adjustment_permissions(uuid,boolean,boolean)
  to authenticated;
grant execute on function public.set_payroll_adjustment_page_label(text)
  to authenticated;
grant execute on function public.payroll_adjustment_worker_rows()
  to authenticated;
grant execute on function public.payroll_adjustment_type_rows()
  to authenticated;
grant execute on function public.payroll_adjustment_rows(uuid,date,date)
  to authenticated;
grant execute on function public.upsert_payroll_adjustment_type(uuid,text,text,boolean)
  to authenticated;
grant execute on function public.create_payroll_adjustment(uuid,uuid,integer,date,text)
  to authenticated;
grant execute on function public.cancel_payroll_adjustment(uuid,text)
  to authenticated;
