create or replace function public.create_company(company_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  new_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(company_name), '') is null then
    raise exception 'Company name is required';
  end if;

  -- This RPC is only for first-company onboarding. Serialize requests for the
  -- same user so duplicate concurrent calls cannot create multiple companies.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  if exists (
    select 1
    from public.company_members cm
    where cm.user_id = v_user_id
  ) then
    raise exception 'User already belongs to a company';
  end if;

  insert into public.companies(name)
  values (trim(company_name))
  returning id into new_company_id;

  insert into public.company_members(company_id, user_id, role)
  values (new_company_id, v_user_id, 'owner');

  return new_company_id;
end;
$$;

revoke execute on function public.create_company(text) from public, anon;
grant execute on function public.create_company(text) to authenticated;
