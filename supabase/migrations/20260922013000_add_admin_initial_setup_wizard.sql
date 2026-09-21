alter table public.sites
  add column if not exists nearest_station text;

create table if not exists public.company_initial_setup_progress (
  company_id uuid primary key references public.companies(id) on delete cascade,
  company_profile_completed boolean not null default false,
  document_requirements_reviewed boolean not null default false,
  first_site_completed boolean not null default false,
  rate_settings_completed boolean not null default false,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.company_initial_setup_progress enable row level security;
revoke all on public.company_initial_setup_progress from anon, authenticated;

create table if not exists public.company_rate_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  overtime_hour_rate_yen integer not null default 0 check (overtime_hour_rate_yen >= 0),
  early_hour_rate_yen integer not null default 0 check (early_hour_rate_yen >= 0),
  night_hour_rate_yen integer not null default 0 check (night_hour_rate_yen >= 0),
  holiday_day_rate_yen integer not null default 0 check (holiday_day_rate_yen >= 0),
  allowance_1_name text,
  allowance_1_amount_yen integer not null default 0 check (allowance_1_amount_yen >= 0),
  allowance_2_name text,
  allowance_2_amount_yen integer not null default 0 check (allowance_2_amount_yen >= 0),
  allowance_3_name text,
  allowance_3_amount_yen integer not null default 0 check (allowance_3_amount_yen >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.company_rate_settings enable row level security;
revoke all on public.company_rate_settings from anon, authenticated;

-- Existing production companies must not be pushed back into onboarding.
insert into public.company_initial_setup_progress(
  company_id,
  company_profile_completed,
  document_requirements_reviewed,
  first_site_completed,
  rate_settings_completed,
  completed_at
)
select
  c.id,
  true,
  true,
  true,
  true,
  now()
from public.companies c
on conflict(company_id) do nothing;

create or replace function private.refresh_initial_setup_completion(
  p_company_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  update public.company_initial_setup_progress p
  set completed_at = case
        when p.company_profile_completed
         and p.document_requirements_reviewed
         and p.first_site_completed
         and p.rate_settings_completed
        then coalesce(p.completed_at, now())
        else null
      end,
      updated_at = now()
  where p.company_id = p_company_id;
end;
$$;

revoke execute on function private.refresh_initial_setup_completion(uuid)
  from public, anon, authenticated;

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

  insert into public.company_approval_assignees(
    company_id, user_id, created_by
  )
  values(new_company_id, v_user_id, v_user_id);

  insert into public.company_initial_setup_progress(company_id)
  values(new_company_id);

  return new_company_id;
end;
$$;

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
set search_path = public, private, pg_temp
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

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    perform public.create_company(trim(p_company_name));

    select cm.company_id, cm.role::text
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
    user_id, display_name, phone, updated_at
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
      updated_at = now()
  where id = v_company_id;

  insert into public.company_private_billing_settings (
    company_id,
    bank_name,
    bank_branch,
    bank_account_type,
    bank_account_number,
    bank_account_holder,
    updated_by,
    updated_at
  )
  values (
    v_company_id,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_bank_branch, '')), ''),
    nullif(trim(coalesce(p_bank_account_type, '')), ''),
    nullif(trim(coalesce(p_bank_account_number, '')), ''),
    nullif(trim(coalesce(p_bank_account_holder, '')), ''),
    v_user_id,
    now()
  )
  on conflict (company_id) do update
  set bank_name = excluded.bank_name,
      bank_branch = excluded.bank_branch,
      bank_account_type = excluded.bank_account_type,
      bank_account_number = excluded.bank_account_number,
      bank_account_holder = excluded.bank_account_holder,
      updated_by = v_user_id,
      updated_at = now();

  if not exists (
    select 1
    from public.workers w
    where w.company_id = v_company_id
      and w.user_id = v_user_id
  ) then
    insert into public.workers(
      company_id,
      affiliation,
      name,
      phone,
      status,
      role,
      user_id
    )
    values(
      v_company_id,
      'employee',
      trim(p_display_name),
      nullif(trim(coalesce(p_phone, '')), ''),
      'active',
      '管理者',
      v_user_id
    );
  else
    update public.workers
    set name = trim(p_display_name),
        phone = nullif(trim(coalesce(p_phone, '')), ''),
        status = 'active',
        updated_at = now()
    where company_id = v_company_id
      and user_id = v_user_id;
  end if;

  insert into public.company_initial_setup_progress(
    company_id,
    company_profile_completed,
    updated_at
  )
  values(v_company_id, true, now())
  on conflict(company_id) do update
  set company_profile_completed = true,
      updated_at = now();

  perform private.refresh_initial_setup_completion(v_company_id);

  return v_company_id;
end;
$$;

create or replace function public.admin_initial_setup_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_progress public.company_initial_setup_progress%rowtype;
begin
  if v_user_id is null then
    return jsonb_build_object('required', false, 'completed', false);
  end if;

  select cm.company_id, cm.role::text
  into v_company_id, v_role
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    return jsonb_build_object('required', false, 'completed', false);
  end if;

  if v_role not in ('owner','admin') then
    return jsonb_build_object('required', false, 'completed', true);
  end if;

  select *
  into v_progress
  from public.company_initial_setup_progress
  where company_id = v_company_id;

  if not found then
    -- Compatibility fail-open for companies created before this contract.
    return jsonb_build_object('required', false, 'completed', true);
  end if;

  return jsonb_build_object(
    'required', v_progress.completed_at is null,
    'completed', v_progress.completed_at is not null,
    'company_profile_completed', v_progress.company_profile_completed,
    'document_requirements_reviewed', v_progress.document_requirements_reviewed,
    'first_site_completed', v_progress.first_site_completed,
    'rate_settings_completed', v_progress.rate_settings_completed
  );
end;
$$;

create or replace function public.mark_initial_document_requirements_reviewed()
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
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

  insert into public.company_initial_setup_progress(
    company_id,
    document_requirements_reviewed,
    updated_at
  )
  values(v_company_id, true, now())
  on conflict(company_id) do update
  set document_requirements_reviewed = true,
      updated_at = now();

  perform private.refresh_initial_setup_completion(v_company_id);
end;
$$;

create or replace function public.save_initial_site(
  p_site_name text,
  p_customer_name text,
  p_site_address text,
  p_nearest_station text,
  p_billing_unit_price_yen integer
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_customer_id uuid;
  v_site_id uuid;
begin
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  if nullif(trim(p_site_name), '') is null
     or nullif(trim(p_customer_name), '') is null
     or nullif(trim(p_site_address), '') is null
     or nullif(trim(p_nearest_station), '') is null then
    raise exception 'site onboarding field missing';
  end if;

  if coalesce(p_billing_unit_price_yen, 0) < 0 then
    raise exception 'invalid site unit price';
  end if;

  select c.id
  into v_customer_id
  from public.customers c
  where c.company_id = v_company_id
    and c.name = trim(p_customer_name)
  limit 1;

  if v_customer_id is null then
    insert into public.customers(company_id, name, billing_name)
    values(v_company_id, trim(p_customer_name), trim(p_customer_name))
    returning id into v_customer_id;
  end if;

  insert into public.sites(
    company_id,
    customer_id,
    name,
    address,
    nearest_station,
    status
  )
  values(
    v_company_id,
    v_customer_id,
    trim(p_site_name),
    trim(p_site_address),
    trim(p_nearest_station),
    'active'
  )
  returning id into v_site_id;

  insert into public.site_financial_settings(
    site_id,
    company_id,
    billing_unit_price_yen,
    updated_by,
    updated_at
  )
  values(
    v_site_id,
    v_company_id,
    p_billing_unit_price_yen,
    v_user_id,
    now()
  )
  on conflict(site_id) do update
  set billing_unit_price_yen = excluded.billing_unit_price_yen,
      updated_by = v_user_id,
      updated_at = now();

  insert into public.company_initial_setup_progress(
    company_id,
    first_site_completed,
    updated_at
  )
  values(v_company_id, true, now())
  on conflict(company_id) do update
  set first_site_completed = true,
      updated_at = now();

  perform private.refresh_initial_setup_completion(v_company_id);

  return v_site_id;
end;
$$;

create or replace function public.save_initial_company_rates(
  p_tax_rate numeric,
  p_welfare_rate numeric,
  p_overtime_hour_rate_yen integer,
  p_early_hour_rate_yen integer,
  p_night_hour_rate_yen integer,
  p_holiday_day_rate_yen integer,
  p_allowance_1_name text default null,
  p_allowance_1_amount_yen integer default 0,
  p_allowance_2_name text default null,
  p_allowance_2_amount_yen integer default 0,
  p_allowance_3_name text default null,
  p_allowance_3_amount_yen integer default 0
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
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  if p_tax_rate < 0 or p_tax_rate > 100
     or p_welfare_rate < 0 or p_welfare_rate > 100
     or p_overtime_hour_rate_yen < 0
     or p_early_hour_rate_yen < 0
     or p_night_hour_rate_yen < 0
     or p_holiday_day_rate_yen < 0
     or p_allowance_1_amount_yen < 0
     or p_allowance_2_amount_yen < 0
     or p_allowance_3_amount_yen < 0 then
    raise exception 'invalid company rate setting';
  end if;

  update public.companies
  set tax_rate = p_tax_rate,
      default_welfare_rate = p_welfare_rate,
      updated_at = now()
  where id = v_company_id;

  insert into public.company_rate_settings(
    company_id,
    overtime_hour_rate_yen,
    early_hour_rate_yen,
    night_hour_rate_yen,
    holiday_day_rate_yen,
    allowance_1_name,
    allowance_1_amount_yen,
    allowance_2_name,
    allowance_2_amount_yen,
    allowance_3_name,
    allowance_3_amount_yen,
    updated_by,
    updated_at
  )
  values(
    v_company_id,
    p_overtime_hour_rate_yen,
    p_early_hour_rate_yen,
    p_night_hour_rate_yen,
    p_holiday_day_rate_yen,
    nullif(trim(coalesce(p_allowance_1_name, '')), ''),
    p_allowance_1_amount_yen,
    nullif(trim(coalesce(p_allowance_2_name, '')), ''),
    p_allowance_2_amount_yen,
    nullif(trim(coalesce(p_allowance_3_name, '')), ''),
    p_allowance_3_amount_yen,
    v_user_id,
    now()
  )
  on conflict(company_id) do update
  set overtime_hour_rate_yen = excluded.overtime_hour_rate_yen,
      early_hour_rate_yen = excluded.early_hour_rate_yen,
      night_hour_rate_yen = excluded.night_hour_rate_yen,
      holiday_day_rate_yen = excluded.holiday_day_rate_yen,
      allowance_1_name = excluded.allowance_1_name,
      allowance_1_amount_yen = excluded.allowance_1_amount_yen,
      allowance_2_name = excluded.allowance_2_name,
      allowance_2_amount_yen = excluded.allowance_2_amount_yen,
      allowance_3_name = excluded.allowance_3_name,
      allowance_3_amount_yen = excluded.allowance_3_amount_yen,
      updated_by = v_user_id,
      updated_at = now();

  insert into public.company_initial_setup_progress(
    company_id,
    rate_settings_completed,
    updated_at
  )
  values(v_company_id, true, now())
  on conflict(company_id) do update
  set rate_settings_completed = true,
      updated_at = now();

  perform private.refresh_initial_setup_completion(v_company_id);
end;
$$;

revoke execute on function public.admin_initial_setup_state() from public, anon;
revoke execute on function public.mark_initial_document_requirements_reviewed() from public, anon;
revoke execute on function public.save_initial_site(text,text,text,text,integer) from public, anon;
revoke execute on function public.save_initial_company_rates(
  numeric,numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer
) from public, anon;

grant execute on function public.admin_initial_setup_state() to authenticated;
grant execute on function public.mark_initial_document_requirements_reviewed() to authenticated;
grant execute on function public.save_initial_site(text,text,text,text,integer) to authenticated;
grant execute on function public.save_initial_company_rates(
  numeric,numeric,integer,integer,integer,integer,text,integer,text,integer,text,integer
) to authenticated;
