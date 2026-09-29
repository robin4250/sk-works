-- Master-controlled product feature availability.
-- Non-destructive: optional features default ON and can be reversibly disabled.

create table if not exists private.master_feature_settings (
  feature_key text primary key
    check (feature_key in ('vehicle_management','route_assignment')),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table private.master_feature_settings enable row level security;
revoke all on private.master_feature_settings from public, anon, authenticated;

insert into private.master_feature_settings(feature_key, enabled)
values
  ('vehicle_management', true),
  ('route_assignment', true)
on conflict (feature_key) do nothing;

create or replace function public.current_master_feature_flags()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null then null
    else jsonb_build_object(
      'vehicle_management',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'vehicle_management'
        ), true),
      'route_assignment',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'route_assignment'
        ), true)
    )
  end;
$$;

revoke all on function public.current_master_feature_flags() from public, anon;
grant execute on function public.current_master_feature_flags() to authenticated;

create or replace function public.set_master_feature_enabled(
  p_feature_key text,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.is_current_master_admin() then
    raise exception 'master administrator access required';
  end if;

  if p_feature_key not in ('vehicle_management','route_assignment') then
    raise exception 'unsupported master feature';
  end if;

  insert into private.master_feature_settings(
    feature_key, enabled, updated_at, updated_by
  )
  values (p_feature_key, p_enabled, now(), auth.uid())
  on conflict (feature_key) do update
    set enabled = excluded.enabled,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;

  return public.current_master_feature_flags();
end;
$$;

revoke all on function public.set_master_feature_enabled(text,boolean)
  from public, anon;
grant execute on function public.set_master_feature_enabled(text,boolean)
  to authenticated;
