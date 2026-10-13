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
  if auth.uid() is null or not public.is_current_user_master_admin() then
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
