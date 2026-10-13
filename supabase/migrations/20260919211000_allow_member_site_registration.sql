create or replace function public.create_basic_site_for_member(
  p_name text,
  p_customer_name text,
  p_address text default null,
  p_starts_at date default null,
  p_ends_at date default null,
  p_manager_name text default null,
  p_status text default 'preparation',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_customer_id uuid;
  v_manager_id uuid;
  v_site_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'company membership not found';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception 'site name is required';
  end if;

  if nullif(trim(coalesce(p_customer_name, '')), '') is null then
    raise exception 'customer name is required';
  end if;

  select c.id
  into v_customer_id
  from public.customers c
  where c.company_id = v_company_id
    and c.name = trim(p_customer_name)
  limit 1;

  if v_customer_id is null then
    insert into public.customers(company_id, name)
    values (v_company_id, trim(p_customer_name))
    returning id into v_customer_id;
  end if;

  if nullif(trim(coalesce(p_manager_name, '')), '') is not null then
    select w.id
    into v_manager_id
    from public.workers w
    where w.company_id = v_company_id
      and w.affiliation = 'employee'
      and w.name = trim(p_manager_name)
      and w.status = 'active'
    limit 1;
  end if;

  v_status := case
    when p_status in ('preparation','active','paused','completed') then p_status
    else 'preparation'
  end;

  insert into public.sites(
    company_id,
    customer_id,
    name,
    address,
    starts_at,
    ends_at,
    manager_worker_id,
    status,
    notes
  )
  values (
    v_company_id,
    v_customer_id,
    trim(p_name),
    nullif(trim(coalesce(p_address, '')), ''),
    p_starts_at,
    p_ends_at,
    v_manager_id,
    v_status,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_site_id;

  return v_site_id;
end;
$$;

revoke execute on function public.create_basic_site_for_member(
  text, text, text, date, date, text, text, text
) from public, anon;

grant execute on function public.create_basic_site_for_member(
  text, text, text, date, date, text, text, text
) to authenticated;
