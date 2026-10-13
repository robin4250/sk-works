alter table public.companies
  add column if not exists corporate_number text;

create or replace function public.company_data_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_role text;
  v public.companies%rowtype;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select company_id,role::text into v_company,v_role
  from public.company_members
  where user_id=v_user
  limit 1;
  if v_company is null or v_role not in ('owner','admin') then
    raise exception 'owner or admin permission required';
  end if;
  select * into v from public.companies where id=v_company;
  return jsonb_build_object(
    'name',coalesce(v.name,''),
    'address',coalesce(v.address,''),
    'corporate_number',coalesce(v.corporate_number,''),
    'phone',coalesce(v.phone,''),
    'fax',coalesce(v.fax,''),
    'email',coalesce(v.email,''),
    'bank_name',coalesce(v.bank_name,''),
    'bank_branch',coalesce(v.bank_branch,''),
    'bank_account_number',coalesce(v.bank_account_number,''),
    'bank_account_holder',coalesce(v.bank_account_holder,'')
  );
end;
$$;

create or replace function public.save_company_data(
  p_name text,
  p_address text,
  p_corporate_number text,
  p_phone text,
  p_fax text,
  p_email text,
  p_bank_name text,
  p_bank_branch text,
  p_bank_account_number text,
  p_bank_account_holder text
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_corporate text:=regexp_replace(coalesce(p_corporate_number,''),'[^0-9]','','g');
begin
  select company_id into v_company
  from public.company_members
  where user_id=v_user and role::text in ('owner','admin')
  limit 1;
  if v_company is null then raise exception 'owner or admin permission required'; end if;
  if v_corporate<>'' and length(v_corporate)<>13 then
    raise exception '法人番号は13桁で入力してください';
  end if;

  update public.companies
  set name=nullif(trim(coalesce(p_name,'')),''),
      address=nullif(trim(coalesce(p_address,'')),''),
      corporate_number=nullif(v_corporate,''),
      phone=nullif(trim(coalesce(p_phone,'')),''),
      fax=nullif(trim(coalesce(p_fax,'')),''),
      email=nullif(trim(coalesce(p_email,'')),''),
      bank_name=nullif(trim(coalesce(p_bank_name,'')),''),
      bank_branch=nullif(trim(coalesce(p_bank_branch,'')),''),
      bank_account_number=nullif(trim(coalesce(p_bank_account_number,'')),''),
      bank_account_holder=nullif(trim(coalesce(p_bank_account_holder,'')),''),
      updated_at=now()
  where id=v_company;
end;
$$;

revoke all on function public.company_data_state() from public;
grant execute on function public.company_data_state() to authenticated;
revoke all on function public.save_company_data(text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.save_company_data(text,text,text,text,text,text,text,text,text,text) to authenticated;
