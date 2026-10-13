create or replace function public.complete_initial_company_profile(
  p_display_name text,
  p_company_name text,
  p_postal_code text default null,
  p_address text default null,
  p_phone text default null,
  p_fax text default null,
  p_email text default null,
  p_bank_name text default null,
  p_bank_branch text default null,
  p_bank_account_type text default null,
  p_bank_account_number text default null,
  p_bank_account_holder text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if nullif(trim(p_display_name), '') is null then
    raise exception 'display name is required';
  end if;

  if nullif(trim(p_company_name), '') is null then
    raise exception 'company name is required';
  end if;

  select cm.company_id, cm.role
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    perform public.create_company(trim(p_company_name));

    select cm.company_id, cm.role
    into v_company_id, v_role
    from public.company_members cm
    where cm.user_id = v_user_id
    limit 1;
  elsif v_role not in ('owner', 'admin') then
    raise exception 'owner or admin role required';
  end if;

  if v_company_id is null then
    raise exception 'company membership was not created';
  end if;

  insert into public.user_profiles (
    user_id,
    display_name,
    phone,
    updated_at
  )
  values (
    v_user_id,
    trim(p_display_name),
    nullif(trim(coalesce(p_phone, '')), ''),
    now()
  )
  on conflict (user_id) do update
  set display_name = excluded.display_name,
      phone = excluded.phone,
      updated_at = now();

  update public.companies
  set name = trim(p_company_name),
      postal_code = nullif(trim(coalesce(p_postal_code, '')), ''),
      address = nullif(trim(coalesce(p_address, '')), ''),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      fax = nullif(trim(coalesce(p_fax, '')), ''),
      email = nullif(trim(coalesce(p_email, '')), ''),
      bank_name = nullif(trim(coalesce(p_bank_name, '')), ''),
      bank_branch = nullif(trim(coalesce(p_bank_branch, '')), ''),
      bank_account_type = nullif(trim(coalesce(p_bank_account_type, '')), ''),
      bank_account_number = nullif(trim(coalesce(p_bank_account_number, '')), ''),
      bank_account_holder = nullif(trim(coalesce(p_bank_account_holder, '')), '')
  where id = v_company_id;

  return v_company_id;
end;
$$;

revoke execute on function public.complete_initial_company_profile(
  text, text, text, text, text, text, text, text, text, text, text, text
) from public, anon;

grant execute on function public.complete_initial_company_profile(
  text, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;
