create or replace function public.update_site_attendance_location(
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_latitude is null
     or p_latitude < -90
     or p_latitude > 90
     or p_longitude is null
     or p_longitude < -180
     or p_longitude > 180 then
    raise exception 'invalid coordinates';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(
       v_company_id,
       'can_manage_attendance'
     ) then
    raise exception 'attendance management permission required';
  end if;

  update public.sites
  set latitude = p_latitude,
      longitude = p_longitude,
      updated_at = now()
  where id = p_site_id
    and company_id = v_company_id;

  if not found then
    raise exception 'site not found';
  end if;
end;
$$;

revoke execute on function public.update_site_attendance_location(
  uuid, double precision, double precision
) from public, anon;

grant execute on function public.update_site_attendance_location(
  uuid, double precision, double precision
) to authenticated;
