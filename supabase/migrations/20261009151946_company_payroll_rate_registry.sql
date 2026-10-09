-- Staged registry only: no seeds, UI wiring, payroll switching or existing table changes.
-- Verified candidate insertion is reserved for a future trusted server publication flow.
create schema payroll_rate_private;
revoke all on schema payroll_rate_private from public, anon, authenticated;
grant usage on schema payroll_rate_private to authenticated;

create table payroll_rate_private.settings (
 company_id uuid not null references public.companies(id),
 item_id text not null,
 version bigint not null check(version > 0),
 value jsonb not null,
 origin text not null check(origin in ('manual','official_candidate')),
 updated_by uuid not null,
 updated_at timestamptz not null,
 primary key(company_id,item_id)
);
-- Standard insurance kinds are single company settings; future period versions
-- must not be introduced by registering a duplicate current item.
create unique index payroll_rate_standard_kind on payroll_rate_private.settings(company_id,(value->>'kind'))
 where value->>'kind' <> 'custom';
create unique index payroll_rate_label on payroll_rate_private.settings(company_id,lower(trim(value->>'label')));
create table payroll_rate_private.candidates (
 company_id uuid not null references public.companies(id),
 candidate_id uuid not null,
 item_id text not null,
 value jsonb not null,
 checked_at timestamptz not null,
 scope_version bigint not null check(scope_version > 0),
 verified_at timestamptz not null,
 verified_by uuid not null,
 verification_evidence text not null check(length(trim(verification_evidence)) > 0),
 primary key(company_id,candidate_id)
);
create index payroll_rate_candidates_item on payroll_rate_private.candidates(company_id,item_id);
create table payroll_rate_private.history (
 company_id uuid not null references public.companies(id),
 item_id text not null,
 version bigint not null,
 before_value jsonb,
 after_value jsonb not null,
 before_origin text,
 after_origin text not null,
 candidate_id uuid,
 actor_id uuid not null,
 changed_at timestamptz not null,
 primary key(company_id,item_id,version)
);
-- Single source for payroll-only company applicability. No address/name copies.
create table payroll_rate_private.company_scope (
 company_id uuid primary key references public.companies(id),
 version bigint not null check(version > 0),
 value jsonb not null,
 updated_by uuid not null,
 updated_at timestamptz not null
);
create table payroll_rate_private.scope_history (
 company_id uuid not null references public.companies(id),
 version bigint not null,
 before_value jsonb,
 after_value jsonb not null,
 actor_id uuid not null,
 changed_at timestamptz not null,
 primary key(company_id,version)
);
alter table payroll_rate_private.company_scope enable row level security;
alter table payroll_rate_private.scope_history enable row level security;
alter table payroll_rate_private.settings enable row level security;
alter table payroll_rate_private.candidates enable row level security;
alter table payroll_rate_private.history enable row level security;
revoke all on all tables in schema payroll_rate_private from public, anon, authenticated;

create function payroll_rate_private.require_admin(p_company_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id
   and cm.user_id=auth.uid() and cm.role::text in ('owner','admin')
 ) then raise exception 'payroll rate admin access denied' using errcode='42501'; end if;
end $$;

create function payroll_rate_private.validate_value(p_value jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare k text; n bigint; v_source jsonb; v_pair record;
begin
 if p_value is null or octet_length(p_value::text) > 32768 then
  raise exception 'rate payload exceeds 32 KiB or is missing' using errcode='22023';
 end if;
 if jsonb_typeof(p_value) is distinct from 'object' or
   p_value - array['kind','label','total','employee','employer','insurance_month','payroll_month','payment_month','source'] <> '{}'::jsonb or
   coalesce(p_value->>'kind','') not in ('health_insurance','nursing_insurance','pension_insurance','employment_insurance','child_support','custom') or
   jsonb_typeof(p_value->'label') is distinct from 'string' or length(trim(p_value->>'label'))=0 or length(p_value->>'label')>80 then
  raise exception 'invalid rate kind or label' using errcode='22023';
 end if;
 foreach k in array array['total','employee','employer'] loop
  if jsonb_typeof(p_value->k) is distinct from 'number' or (p_value->>k) !~ '^[0-9]{1,9}$' then
   raise exception 'rate must be fixed precision integer' using errcode='22023';
  end if;
  n := (p_value->>k)::bigint;
  if n > 100000000 then raise exception 'rate exceeds 100 percent' using errcode='22023'; end if;
 end loop;
 if (p_value->>'total')::bigint <> (p_value->>'employee')::bigint + (p_value->>'employer')::bigint then
  raise exception 'explicit shares must sum to total' using errcode='22023';
 end if;
 foreach k in array array['insurance_month','payroll_month','payment_month'] loop
  if jsonb_typeof(p_value->k) is distinct from 'string' or (p_value->>k) !~ '^[0-9]{4}-(0[1-9]|1[0-2])-01$' then
   raise exception 'separate ISO month dates required' using errcode='22023';
  end if;
  perform (p_value->>k)::date;
 end loop;
 v_source := p_value->'source';
 if jsonb_typeof(v_source) is distinct from 'object' or
  v_source - array['url','publisher','document_hash','applicability'] <> '{}'::jsonb or
  jsonb_typeof(v_source->'url') is distinct from 'string' or
  (v_source->>'url') !~ '^https://[^/[:space:]]+' or length(v_source->>'url')>2048 or
  jsonb_typeof(v_source->'publisher') is distinct from 'string' or length(trim(v_source->>'publisher'))=0 or length(v_source->>'publisher')>200 or
  jsonb_typeof(v_source->'document_hash') is distinct from 'string' or length(trim(v_source->>'document_hash'))=0 or length(v_source->>'document_hash')>256 or
  jsonb_typeof(v_source->'applicability') is distinct from 'object' or v_source->'applicability'='{}'::jsonb then
  raise exception 'source and applicability required' using errcode='22023';
 end if;
 if (select count(*) from jsonb_object_keys(v_source->'applicability'))>20 then
  raise exception 'too many applicability conditions' using errcode='22023';
 end if;
 for v_pair in select key,value from jsonb_each(v_source->'applicability') loop
  if length(trim(v_pair.key))=0 or length(v_pair.key)>80 or
     jsonb_typeof(v_pair.value) is distinct from 'string' or
     length(trim(v_pair.value #>> '{}'))=0 or length(v_pair.value #>> '{}')>512 then
   raise exception 'applicability requires bounded string keys and values' using errcode='22023';
  end if;
 end loop;
end $$;

create function payroll_rate_private.read_rates(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_items jsonb; v_candidates jsonb; v_history jsonb; v_scope jsonb; v_scope_history jsonb;
begin
 perform payroll_rate_private.require_admin(p_company_id);
 select coalesce(jsonb_agg(jsonb_build_object('item_id',s.item_id,'version',s.version,'value',s.value,'origin',s.origin) order by s.item_id),'[]'::jsonb)
 into v_items from payroll_rate_private.settings s where s.company_id=p_company_id;
 select coalesce(jsonb_agg(jsonb_build_object('candidate_id',c.candidate_id,'item_id',c.item_id,'value',c.value,'checked_at',c.checked_at,'scope_version',c.scope_version) order by c.checked_at desc),'[]'::jsonb)
 into v_candidates from payroll_rate_private.candidates c where c.company_id=p_company_id;
 select coalesce(jsonb_agg(to_jsonb(h) - 'company_id' order by h.changed_at desc,h.version desc),'[]'::jsonb)
 into v_history from payroll_rate_private.history h where h.company_id=p_company_id;
 select to_jsonb(s) - 'company_id' into v_scope from payroll_rate_private.company_scope s where s.company_id=p_company_id;
 select coalesce(jsonb_agg(to_jsonb(h) - 'company_id' order by h.version desc),'[]'::jsonb)
 into v_scope_history from payroll_rate_private.scope_history h where h.company_id=p_company_id;
 return jsonb_build_object('items',v_items,'candidates',v_candidates,'history',v_history,
  'company_scope',v_scope,'scope_history',v_scope_history);
end $$;

create function payroll_rate_private.write_rate(p_company_id uuid,p_item_id text,p_expected_version bigint,p_value jsonb,p_confirmed boolean,p_candidate_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before payroll_rate_private.settings%rowtype; v_value jsonb;
 v_origin text; v_version bigint; v_at timestamptz; v_scope_version bigint;
begin
 perform payroll_rate_private.require_admin(p_company_id);
 if p_item_id is null or p_expected_version is null or p_expected_version < 0 or p_confirmed is distinct from true then
  raise exception 'explicit rate, months and source confirmation required' using errcode='22023';
 end if;
 -- Serializes company writes, including first insertion and duplicate labels.
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':payroll-rate-registry',0));
 select * into v_before from payroll_rate_private.settings where company_id=p_company_id and item_id=p_item_id for update;
 if coalesce(v_before.version,0) <> p_expected_version then
  raise exception 'rate version conflict' using errcode='40001';
 end if;
 if p_candidate_id is null then
  v_value := p_value; v_origin := 'manual';
 else
  select c.value,c.scope_version into v_value,v_scope_version from payroll_rate_private.candidates c
   where c.company_id=p_company_id and c.item_id=p_item_id and c.candidate_id=p_candidate_id for share;
  if not found then raise exception 'verified company candidate not found' using errcode='22023'; end if;
  if not exists(select 1 from payroll_rate_private.company_scope s
   where s.company_id=p_company_id and s.version=v_scope_version) then
   raise exception 'candidate company scope version conflict' using errcode='40001';
  end if;
  v_origin := 'official_candidate';
 end if;
 perform payroll_rate_private.validate_value(v_value);
 if (v_value->>'kind' <> 'custom' and p_item_id <> v_value->>'kind') or
    (v_value->>'kind' = 'custom' and p_item_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
  raise exception 'standard kind ID or custom UUID required' using errcode='22023';
 end if;
 if v_before.version is not null and v_before.value->>'kind' <> v_value->>'kind' then
  raise exception 'existing item kind cannot change' using errcode='22023';
 end if;
 v_version := p_expected_version+1;
 v_at := clock_timestamp();
 insert into payroll_rate_private.settings(company_id,item_id,version,value,origin,updated_by,updated_at)
 values(p_company_id,p_item_id,v_version,v_value,v_origin,auth.uid(),v_at)
 on conflict(company_id,item_id) do update set version=excluded.version,value=excluded.value,origin=excluded.origin,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 insert into payroll_rate_private.history(company_id,item_id,version,before_value,after_value,before_origin,after_origin,candidate_id,actor_id,changed_at)
 values(p_company_id,p_item_id,v_version,v_before.value,v_value,v_before.origin,v_origin,p_candidate_id,auth.uid(),v_at);
 return jsonb_build_object('item_id',p_item_id,'version',v_version,'value',v_value,'origin',v_origin);
end $$;

create function payroll_rate_private.save_scope(p_company_id uuid,p_expected_version bigint,p_value jsonb,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before payroll_rate_private.company_scope%rowtype; v_version bigint; v_at timestamptz;
begin
 perform payroll_rate_private.require_admin(p_company_id);
 if p_expected_version is null or p_expected_version<0 or p_confirmed is distinct from true then
  raise exception 'explicit company scope confirmation required' using errcode='22023';
 end if;
 if p_value is null or octet_length(p_value::text)>1024 or jsonb_typeof(p_value) is distinct from 'object' or
  p_value - array['insurer','prefecture','employment_business'] <> '{}'::jsonb or
  jsonb_typeof(p_value->'insurer') is distinct from 'string' or
  coalesce(p_value->>'insurer','') not in ('kyokai','union','other','unconfigured') or
  not(p_value ? 'prefecture') or not(p_value ? 'employment_business') then
  raise exception 'invalid company scope' using errcode='22023';
 end if;
 if p_value->'prefecture' <> 'null'::jsonb and
  (jsonb_typeof(p_value->'prefecture') is distinct from 'string' or
   p_value->>'prefecture' not in ('北海道','青森県','岩手県','宮城県','秋田県','山形県','福島県','茨城県','栃木県','群馬県','埼玉県','千葉県','東京都','神奈川県','新潟県','富山県','石川県','福井県','山梨県','長野県','岐阜県','静岡県','愛知県','三重県','滋賀県','京都府','大阪府','兵庫県','奈良県','和歌山県','鳥取県','島根県','岡山県','広島県','山口県','徳島県','香川県','愛媛県','高知県','福岡県','佐賀県','長崎県','熊本県','大分県','宮崎県','鹿児島県','沖縄県')) then
  raise exception 'invalid prefecture; never infer from address' using errcode='22023';
 end if;
 if p_value->'employment_business' <> 'null'::jsonb and
  (jsonb_typeof(p_value->'employment_business') is distinct from 'string' or
   p_value->>'employment_business' not in ('general','agriculture_forestry_fisheries_sake','construction')) then
  raise exception 'invalid employment business classification' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':payroll-rate-registry',0));
 select * into v_before from payroll_rate_private.company_scope where company_id=p_company_id for update;
 if coalesce(v_before.version,0) <> p_expected_version then
  raise exception 'company scope version conflict' using errcode='40001';
 end if;
 v_version := p_expected_version+1; v_at := clock_timestamp();
 insert into payroll_rate_private.company_scope(company_id,version,value,updated_by,updated_at)
 values(p_company_id,v_version,p_value,auth.uid(),v_at)
 on conflict(company_id) do update set version=excluded.version,value=excluded.value,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 insert into payroll_rate_private.scope_history(company_id,version,before_value,after_value,actor_id,changed_at)
 values(p_company_id,v_version,v_before.value,p_value,auth.uid(),v_at);
 return jsonb_build_object('version',v_version,'value',p_value,'updated_by',auth.uid(),'updated_at',v_at);
end $$;

create function public.save_company_payroll_rate_scope(p_company_id uuid,p_expected_version bigint,p_value jsonb,p_confirmed boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select payroll_rate_private.save_scope(p_company_id,p_expected_version,p_value,p_confirmed);
$$;

create function public.read_company_payroll_rates(p_company_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select payroll_rate_private.read_rates(p_company_id);
$$;
create function public.save_manual_company_payroll_rate(p_company_id uuid,p_item_id text,p_expected_version bigint,p_value jsonb,p_confirmed boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select payroll_rate_private.write_rate(p_company_id,p_item_id,p_expected_version,p_value,p_confirmed,null);
$$;
create function public.apply_company_payroll_rate_candidate(p_company_id uuid,p_item_id text,p_candidate_id uuid,p_expected_version bigint,p_confirmed boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_candidate_id is null then raise exception 'candidate ID required' using errcode='22023'; end if;
 return payroll_rate_private.write_rate(p_company_id,p_item_id,p_expected_version,null,p_confirmed,p_candidate_id);
end $$;

revoke all on all functions in schema payroll_rate_private from public, anon, authenticated;
-- Private APIs remain checked even if called directly; validator is not exposed.
grant execute on function payroll_rate_private.read_rates(uuid), payroll_rate_private.save_scope(uuid,bigint,jsonb,boolean), payroll_rate_private.write_rate(uuid,text,bigint,jsonb,boolean,uuid) to authenticated;
revoke all on function public.read_company_payroll_rates(uuid), public.save_company_payroll_rate_scope(uuid,bigint,jsonb,boolean), public.save_manual_company_payroll_rate(uuid,text,bigint,jsonb,boolean), public.apply_company_payroll_rate_candidate(uuid,text,uuid,bigint,boolean) from public, anon, authenticated;
grant execute on function public.read_company_payroll_rates(uuid), public.save_company_payroll_rate_scope(uuid,bigint,jsonb,boolean), public.save_manual_company_payroll_rate(uuid,text,bigint,jsonb,boolean), public.apply_company_payroll_rate_candidate(uuid,text,uuid,bigint,boolean) to authenticated;
