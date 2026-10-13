create extension if not exists pgcrypto;

alter table public.companies
  add column if not exists postal_code text,
  add column if not exists address text,
  add column if not exists phone text,
  add column if not exists fax text,
  add column if not exists email text,
  add column if not exists bank_name text,
  add column if not exists bank_branch text,
  add column if not exists bank_account_type text,
  add column if not exists bank_account_number text,
  add column if not exists bank_account_holder text;

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

drop policy if exists "users can read own profile" on public.user_profiles;
create policy "users can read own profile"
on public.user_profiles
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "users can update own profile" on public.user_profiles;
create policy "users can update own profile"
on public.user_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "users can insert own profile" on public.user_profiles;
create policy "users can insert own profile"
on public.user_profiles
for insert
to authenticated
with check (user_id = auth.uid());

create table if not exists public.user_secondary_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  password_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_secondary_credentials enable row level security;

revoke all on public.user_secondary_credentials from anon, authenticated;

create or replace function public.secondary_password_configured()
returns boolean
language sql
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_secondary_credentials usc
    where usc.user_id = auth.uid()
  );
$$;

create or replace function public.set_secondary_password(p_password text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'secondary password must be at least 8 characters';
  end if;

  insert into public.user_secondary_credentials (
    user_id,
    password_hash,
    failed_attempts,
    locked_until,
    updated_at
  )
  values (
    v_user_id,
    crypt(p_password, gen_salt('bf', 12)),
    0,
    null,
    now()
  )
  on conflict (user_id) do update
  set password_hash = excluded.password_hash,
      failed_attempts = 0,
      locked_until = null,
      updated_at = now();
end;
$$;

create or replace function public.verify_secondary_password(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.user_secondary_credentials%rowtype;
  v_ok boolean;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select *
  into v_row
  from public.user_secondary_credentials
  where user_id = v_user_id
  for update;

  if not found then
    return false;
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    raise exception 'secondary password temporarily locked';
  end if;

  v_ok := v_row.password_hash = crypt(coalesce(p_password, ''), v_row.password_hash);

  if v_ok then
    update public.user_secondary_credentials
    set failed_attempts = 0,
        locked_until = null,
        updated_at = now()
    where user_id = v_user_id;
    return true;
  end if;

  update public.user_secondary_credentials
  set failed_attempts = failed_attempts + 1,
      locked_until = case
        when failed_attempts + 1 >= 5 then now() + interval '5 minutes'
        else null
      end,
      updated_at = now()
  where user_id = v_user_id;

  return false;
end;
$$;

revoke execute on function public.secondary_password_configured() from public, anon;
revoke execute on function public.set_secondary_password(text) from public, anon;
revoke execute on function public.verify_secondary_password(text) from public, anon;

grant execute on function public.secondary_password_configured() to authenticated;
grant execute on function public.set_secondary_password(text) to authenticated;
grant execute on function public.verify_secondary_password(text) to authenticated;

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

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null then
    perform public.create_company(trim(p_company_name));

    select cm.company_id
    into v_company_id
    from public.company_members cm
    where cm.user_id = v_user_id
    limit 1;
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
