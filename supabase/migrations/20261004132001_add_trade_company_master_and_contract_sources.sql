-- Mirrors production migration 20261004132001.
-- Unified trade-company master for linked and non-linked customers/subcontractors.

create table if not exists public.trade_companies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  postal_code text,
  address text,
  phone text,
  email text,
  corporate_number text,
  trade_role text not null default 'customer'
    check (trade_role in ('customer','subcontractor','both')),
  linked_company_id uuid references public.companies(id) on delete set null,
  link_status text not null default 'local'
    check (link_status in ('local','merge_pending','linked')),
  customer_id uuid references public.customers(id) on delete set null,
  partner_company_id uuid references public.partner_companies(id) on delete set null,
  notes text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (linked_company_id is null or linked_company_id <> company_id)
);

create index if not exists trade_companies_company_name_idx
  on public.trade_companies(company_id, lower(name));
create index if not exists trade_companies_linked_company_idx
  on public.trade_companies(linked_company_id)
  where linked_company_id is not null;

create table if not exists public.trade_company_contracts (
  company_id uuid not null references public.companies(id) on delete cascade,
  trade_company_id uuid not null references public.trade_companies(id) on delete cascade,
  contract_method text not null default 'none'
    check (contract_method in ('none','daily','monthly','square_meter','contract')),
  daily_rate_yen integer not null default 0 check (daily_rate_yen >= 0),
  monthly_rate_yen integer not null default 0 check (monthly_rate_yen >= 0),
  square_meter_unit_price_yen integer not null default 0 check (square_meter_unit_price_yen >= 0),
  square_meter_quantity numeric(12,3) not null default 0 check (square_meter_quantity >= 0),
  contract_amount_yen integer not null default 0 check (contract_amount_yen >= 0),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key(company_id, trade_company_id),
  check (
    contract_method <> 'square_meter'
    or (square_meter_unit_price_yen > 0 and square_meter_quantity > 0)
  )
);

create table if not exists public.site_calculation_source_preferences (
  company_id uuid not null references public.companies(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  output_type text not null
    check (output_type in ('invoice','payment_certificate','payroll')),
  trade_company_id uuid references public.trade_companies(id) on delete cascade,
  source text not null check (source in ('site','trade_company')),
  selected_by uuid,
  selected_at timestamptz not null default now(),
  primary key(company_id, site_id, output_type)
);

alter table public.trade_companies enable row level security;
alter table public.trade_company_contracts enable row level security;
alter table public.site_calculation_source_preferences enable row level security;

create or replace function private.current_company_admin_id()
returns uuid
language sql
stable
security definer
set search_path=''
as $$
  select cm.company_id
  from public.company_members cm
  where cm.user_id=auth.uid()
    and cm.role::text in ('owner','admin')
  limit 1
$$;

revoke all on function private.current_company_admin_id()
from public,anon,authenticated;

create or replace function private.ensure_trade_company_legacy_links(p_trade_company_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  tc public.trade_companies%rowtype;
  cid uuid;
  legacy_customer uuid;
  legacy_partner uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  select * into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid
  for update;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  if tc.trade_role in ('customer','both') then
    legacy_customer:=tc.customer_id;
    if legacy_customer is null then
      select c.id into legacy_customer
      from public.customers c
      where c.company_id=cid and lower(trim(c.name))=lower(trim(tc.name))
      order by c.created_at limit 1;
    end if;
    if legacy_customer is null then
      insert into public.customers(company_id,name,billing_name,billing_address)
      values(cid,tc.name,tc.name,tc.address)
      returning id into legacy_customer;
    end if;
  end if;

  if tc.trade_role in ('subcontractor','both') then
    legacy_partner:=tc.partner_company_id;
    if legacy_partner is null then
      select p.id into legacy_partner
      from public.partner_companies p
      where p.company_id=cid and lower(trim(p.name))=lower(trim(tc.name))
      order by p.created_at limit 1;
    end if;
    if legacy_partner is null then
      insert into public.partner_companies(
        company_id,name,phone,email,address,postal_code,trade_role,status
      )
      values(cid,tc.name,tc.phone,tc.email,tc.address,tc.postal_code,'subcontractor','active')
      returning id into legacy_partner;
    end if;
  end if;

  update public.trade_companies
  set customer_id=coalesce(legacy_customer,customer_id),
      partner_company_id=coalesce(legacy_partner,partner_company_id),
      updated_by=auth.uid(),
      updated_at=now()
  where id=tc.id;
end
$$;

revoke all on function private.ensure_trade_company_legacy_links(uuid)
from public,anon,authenticated;

create or replace function private.save_trade_company(
  p_id uuid,
  p_name text,
  p_trade_role text,
  p_postal_code text default null,
  p_address text default null,
  p_phone text default null,
  p_email text default null,
  p_corporate_number text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare cid uuid; rid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if nullif(trim(p_name),'') is null then raise exception '会社名を入力してください。'; end if;
  if p_trade_role not in ('customer','subcontractor','both') then
    raise exception '取引区分を確認してください。';
  end if;

  if p_id is null then
    insert into public.trade_companies(
      company_id,name,trade_role,postal_code,address,phone,email,corporate_number,
      notes,created_by,updated_by
    )
    values(
      cid,trim(p_name),p_trade_role,nullif(trim(p_postal_code),''),
      nullif(trim(p_address),''),nullif(trim(p_phone),''),
      nullif(trim(p_email),''),nullif(trim(p_corporate_number),''),
      nullif(trim(p_notes),''),auth.uid(),auth.uid()
    )
    returning id into rid;
  else
    update public.trade_companies
    set name=trim(p_name),trade_role=p_trade_role,
        postal_code=nullif(trim(p_postal_code),''),
        address=nullif(trim(p_address),''),
        phone=nullif(trim(p_phone),''),
        email=nullif(trim(p_email),''),
        corporate_number=nullif(trim(p_corporate_number),''),
        notes=nullif(trim(p_notes),''),
        updated_by=auth.uid(),updated_at=now()
    where id=p_id and company_id=cid
    returning id into rid;
    if rid is null then raise exception '取引会社が見つかりません。'; end if;
  end if;

  perform private.ensure_trade_company_legacy_links(rid);
  return rid;
end
$$;

revoke all on function private.save_trade_company(uuid,text,text,text,text,text,text,text,text)
from public,anon,authenticated;

create or replace function private.trade_company_workspace()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare cid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',tc.id,'name',tc.name,'postal_code',tc.postal_code,
        'address',tc.address,'phone',tc.phone,'email',tc.email,
        'corporate_number',tc.corporate_number,'trade_role',tc.trade_role,
        'linked_company_id',tc.linked_company_id,'link_status',tc.link_status,
        'customer_id',tc.customer_id,'partner_company_id',tc.partner_company_id,
        'notes',tc.notes,'contract_method',coalesce(ct.contract_method,'none'),
        'daily_rate_yen',coalesce(ct.daily_rate_yen,0),
        'monthly_rate_yen',coalesce(ct.monthly_rate_yen,0),
        'square_meter_unit_price_yen',coalesce(ct.square_meter_unit_price_yen,0),
        'square_meter_quantity',coalesce(ct.square_meter_quantity,0),
        'contract_amount_yen',coalesce(ct.contract_amount_yen,0)
      ) order by tc.name
    )
    from public.trade_companies tc
    left join public.trade_company_contracts ct
      on ct.company_id=tc.company_id and ct.trade_company_id=tc.id
    where tc.company_id=cid
  ),'[]'::jsonb);
end
$$;

revoke all on function private.trade_company_workspace()
from public,anon,authenticated;

create or replace function private.trade_company_link_candidates(p_trade_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare cid uuid; tc public.trade_companies%rowtype;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  select * into tc from public.trade_companies
  where id=p_trade_company_id and company_id=cid;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  return coalesce((
    select jsonb_agg(candidate order by (candidate->>'match_score')::int desc, candidate->>'company_name')
    from (
      select jsonb_build_object(
        'company_id',c.id,'company_name',c.name,'phone',c.phone,
        'address',c.address,'corporate_number',c.corporate_number,
        'match_score',
          (case when nullif(trim(coalesce(tc.corporate_number,'')),'') is not null
                  and c.corporate_number=tc.corporate_number then 100 else 0 end)
          +(case when regexp_replace(coalesce(tc.phone,''),'[^0-9]','','g') <> ''
                   and regexp_replace(coalesce(c.phone,''),'[^0-9]','','g')
                     =regexp_replace(coalesce(tc.phone,''),'[^0-9]','','g') then 40 else 0 end)
          +(case when lower(regexp_replace(coalesce(c.name,''),'[[:space:]]','','g'))
                     =lower(regexp_replace(coalesce(tc.name,''),'[[:space:]]','','g')) then 30 else 0 end)
          +(case when nullif(trim(coalesce(tc.address,'')),'') is not null
                   and lower(regexp_replace(coalesce(c.address,''),'[[:space:]]','','g'))
                     =lower(regexp_replace(coalesce(tc.address,''),'[[:space:]]','','g')) then 20 else 0 end)
      ) candidate
      from public.companies c
      where c.id<>cid
    ) candidates
    where (candidate->>'match_score')::int > 0
  ),'[]'::jsonb);
end
$$;

revoke all on function private.trade_company_link_candidates(uuid)
from public,anon,authenticated;

create or replace function private.confirm_trade_company_link(
  p_trade_company_id uuid,
  p_linked_company_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare cid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if not exists(select 1 from public.companies c where c.id=p_linked_company_id and c.id<>cid) then
    raise exception '連携先会社が見つかりません。';
  end if;
  update public.trade_companies
  set linked_company_id=p_linked_company_id,
      link_status='linked',
      updated_by=auth.uid(),
      updated_at=now()
  where id=p_trade_company_id and company_id=cid;
  if not found then raise exception '取引会社が見つかりません。'; end if;
end
$$;

revoke all on function private.confirm_trade_company_link(uuid,uuid)
from public,anon,authenticated;

create or replace function private.save_trade_company_contract(
  p_trade_company_id uuid,
  p_contract_method text,
  p_daily_rate_yen integer default 0,
  p_monthly_rate_yen integer default 0,
  p_square_meter_unit_price_yen integer default 0,
  p_square_meter_quantity numeric default 0,
  p_contract_amount_yen integer default 0
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare cid uuid; tc public.trade_companies%rowtype;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  select * into tc from public.trade_companies
  where id=p_trade_company_id and company_id=cid;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  if p_contract_method not in ('none','daily','monthly','square_meter','contract') then
    raise exception '契約方式を確認してください。';
  end if;
  if p_contract_method='square_meter' and
     (coalesce(p_square_meter_unit_price_yen,0)<=0 or coalesce(p_square_meter_quantity,0)<=0) then
    raise exception '平米単価と平米数を入力してください。';
  end if;

  insert into public.trade_company_contracts(
    company_id,trade_company_id,contract_method,daily_rate_yen,monthly_rate_yen,
    square_meter_unit_price_yen,square_meter_quantity,contract_amount_yen,
    updated_by,updated_at
  )
  values(
    cid,p_trade_company_id,p_contract_method,
    greatest(coalesce(p_daily_rate_yen,0),0),
    greatest(coalesce(p_monthly_rate_yen,0),0),
    greatest(coalesce(p_square_meter_unit_price_yen,0),0),
    greatest(coalesce(p_square_meter_quantity,0),0),
    greatest(coalesce(p_contract_amount_yen,0),0),
    auth.uid(),now()
  )
  on conflict(company_id,trade_company_id) do update
  set contract_method=excluded.contract_method,
      daily_rate_yen=excluded.daily_rate_yen,
      monthly_rate_yen=excluded.monthly_rate_yen,
      square_meter_unit_price_yen=excluded.square_meter_unit_price_yen,
      square_meter_quantity=excluded.square_meter_quantity,
      contract_amount_yen=excluded.contract_amount_yen,
      updated_by=auth.uid(),
      updated_at=now();

  if tc.partner_company_id is not null then
    insert into public.partner_payment_settings(
      company_id,partner_company_id,daily_rate_yen,updated_at
    )
    values(
      cid,tc.partner_company_id,
      case when p_contract_method='daily'
        then greatest(coalesce(p_daily_rate_yen,0),0) else 0 end,
      now()
    )
    on conflict(company_id,partner_company_id) do update
    set daily_rate_yen=excluded.daily_rate_yen,updated_at=now();
  end if;
end
$$;

revoke all on function private.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer)
from public,anon,authenticated;

create or replace function private.select_site_calculation_source(
  p_site_id uuid,
  p_output_type text,
  p_trade_company_id uuid,
  p_source text
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare cid uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  if p_output_type not in ('invoice','payment_certificate','payroll') then
    raise exception '計算対象を確認してください。';
  end if;
  if p_source not in ('site','trade_company') then
    raise exception '計算元を選択してください。';
  end if;
  if not exists(select 1 from public.sites s where s.id=p_site_id and s.company_id=cid) then
    raise exception '現場が見つかりません。';
  end if;
  if p_source='trade_company' and not exists(
    select 1 from public.trade_companies tc
    where tc.id=p_trade_company_id and tc.company_id=cid
  ) then
    raise exception '取引会社が見つかりません。';
  end if;

  insert into public.site_calculation_source_preferences(
    company_id,site_id,output_type,trade_company_id,source,selected_by,selected_at
  )
  values(cid,p_site_id,p_output_type,p_trade_company_id,p_source,auth.uid(),now())
  on conflict(company_id,site_id,output_type) do update
  set trade_company_id=excluded.trade_company_id,
      source=excluded.source,
      selected_by=auth.uid(),
      selected_at=now();
end
$$;

revoke all on function private.select_site_calculation_source(uuid,text,uuid,text)
from public,anon,authenticated;

create or replace function public.trade_company_workspace()
returns jsonb language sql set search_path=''
as $$ select private.trade_company_workspace() $$;

create or replace function public.save_trade_company(
  p_id uuid,p_name text,p_trade_role text,p_postal_code text default null,
  p_address text default null,p_phone text default null,p_email text default null,
  p_corporate_number text default null,p_notes text default null
)
returns uuid language sql set search_path=''
as $$ select private.save_trade_company(
  p_id,p_name,p_trade_role,p_postal_code,p_address,p_phone,p_email,p_corporate_number,p_notes
) $$;

create or replace function public.trade_company_link_candidates(p_trade_company_id uuid)
returns jsonb language sql set search_path=''
as $$ select private.trade_company_link_candidates(p_trade_company_id) $$;

create or replace function public.confirm_trade_company_link(
  p_trade_company_id uuid,p_linked_company_id uuid
)
returns void language sql set search_path=''
as $$ select private.confirm_trade_company_link(p_trade_company_id,p_linked_company_id) $$;

create or replace function public.save_trade_company_contract(
  p_trade_company_id uuid,p_contract_method text,p_daily_rate_yen integer default 0,
  p_monthly_rate_yen integer default 0,p_square_meter_unit_price_yen integer default 0,
  p_square_meter_quantity numeric default 0,p_contract_amount_yen integer default 0
)
returns void language sql set search_path=''
as $$ select private.save_trade_company_contract(
  p_trade_company_id,p_contract_method,p_daily_rate_yen,p_monthly_rate_yen,
  p_square_meter_unit_price_yen,p_square_meter_quantity,p_contract_amount_yen
) $$;

create or replace function public.select_site_calculation_source(
  p_site_id uuid,p_output_type text,p_trade_company_id uuid,p_source text
)
returns void language sql set search_path=''
as $$ select private.select_site_calculation_source(
  p_site_id,p_output_type,p_trade_company_id,p_source
) $$;

revoke all on function public.trade_company_workspace() from public,anon;
revoke all on function public.save_trade_company(uuid,text,text,text,text,text,text,text,text) from public,anon;
revoke all on function public.trade_company_link_candidates(uuid) from public,anon;
revoke all on function public.confirm_trade_company_link(uuid,uuid) from public,anon;
revoke all on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) from public,anon;
revoke all on function public.select_site_calculation_source(uuid,text,uuid,text) from public,anon;

grant execute on function public.trade_company_workspace() to authenticated;
grant execute on function public.save_trade_company(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.trade_company_link_candidates(uuid) to authenticated;
grant execute on function public.confirm_trade_company_link(uuid,uuid) to authenticated;
grant execute on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) to authenticated;
grant execute on function public.select_site_calculation_source(uuid,text,uuid,text) to authenticated;
