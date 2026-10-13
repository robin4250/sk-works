-- Staged private metadata only. No bucket, bytes upload, PDF parser or tax engine.
create schema income_tax_private;
revoke all on schema income_tax_private from public,anon,authenticated;
grant usage on schema income_tax_private to authenticated;
create table income_tax_private.documents (
 company_id uuid not null references public.companies(id) on delete cascade,
 table_id uuid not null,
 version bigint not null check(version>0),
 value jsonb not null,
 registered_by uuid not null,
 registered_at timestamptz not null,
 primary key(company_id,table_id)
);
-- No client insertion/approval API. Future trusted verifier must prove document
-- identity AND separately validated calculation artifacts before inserting.
create table income_tax_private.verifications (
 company_id uuid not null references public.companies(id) on delete cascade,
 table_id uuid not null,
 metadata_version bigint not null check(metadata_version>0),
 document_hash text not null check(document_hash ~ '^[0-9a-f]{64}$'),
 storage_path text not null,
 official_verified_by uuid not null,
 official_verified_at timestamptz not null,
 verification_evidence text not null check(length(trim(verification_evidence)) between 1 and 2000),
 calculation_rules_hash text,
 calculation_rules_version text,
 calculation_verified_by uuid,
 calculation_verified_at timestamptz,
 primary key(company_id,table_id,metadata_version),
 check((calculation_rules_hash is null and calculation_rules_version is null and calculation_verified_by is null and calculation_verified_at is null) or
  (calculation_rules_hash is not null and calculation_rules_hash ~ '^[0-9a-f]{64}$' and
   calculation_rules_version is not null and length(trim(calculation_rules_version)) between 1 and 100 and
   calculation_verified_by is not null and calculation_verified_at is not null))
);
-- Logical attribution retains metadata/version evidence without blocking company deletion.
create table income_tax_private.history (
 event_id bigint generated always as identity primary key,
 company_id uuid not null,
 table_id uuid not null,
 version bigint not null,
 event_type text not null check(event_type in ('registration','verification')),
 before_value jsonb,
 after_value jsonb,
 actor_id uuid not null,
 changed_at timestamptz not null
);
create index income_tax_history_company on income_tax_private.history(company_id,event_id desc);
alter table income_tax_private.documents enable row level security;
alter table income_tax_private.verifications enable row level security;
alter table income_tax_private.history enable row level security;
revoke all on all tables in schema income_tax_private from public,anon,authenticated;
revoke all on all sequences in schema income_tax_private from public,anon,authenticated;

create function income_tax_private.require_admin(p_company_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id
  and cm.user_id=auth.uid() and cm.role::text in ('owner','admin')) then
  raise exception 'income tax admin access denied' using errcode='42501';
 end if;
 perform 1 from public.companies c where c.id=p_company_id for key share;
 if not found then raise exception 'income tax admin access denied' using errcode='42501'; end if;
end $$;

create function income_tax_private.validate_metadata(p_company_id uuid,p_table_id uuid,p_version bigint,p_value jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare v_year integer; v_start date; v_end date; k text;
begin
 if p_value is null or octet_length(p_value::text)>8192 or jsonb_typeof(p_value) is distinct from 'object' or
  p_value - array['calendar_year','kind','starts_on','ends_before','document_hash','storage_path','source_url','publisher','file_name'] <> '{}'::jsonb or
  jsonb_typeof(p_value->'calendar_year') is distinct from 'number' or (p_value->>'calendar_year') !~ '^[1-9][0-9]{3}$' or
  jsonb_typeof(p_value->'kind') is distinct from 'string' or
  p_value->>'kind' not in ('monthly','daily','bonus','computer_calculation') then
  raise exception 'invalid income tax metadata kind/year' using errcode='22023';
 end if;
 v_year := (p_value->>'calendar_year')::integer;
 if v_year>9998 then raise exception 'calendar year exceeds supported date range' using errcode='22023'; end if;
 foreach k in array array['starts_on','ends_before'] loop
  if jsonb_typeof(p_value->k) is distinct from 'string' or (p_value->>k) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
   raise exception 'civil YYYY-MM-DD required' using errcode='22023';
  end if;
 end loop;
 v_start := (p_value->>'starts_on')::date; v_end := (p_value->>'ends_before')::date;
 if extract(year from v_start)::integer<>v_year or v_end<=v_start or v_end>make_date(v_year+1,1,1) then
  raise exception 'income tax period outside calendar year' using errcode='22023';
 end if;
 if jsonb_typeof(p_value->'document_hash') is distinct from 'string' or (p_value->>'document_hash') !~ '^[0-9a-f]{64}$' or
  jsonb_typeof(p_value->'storage_path') is distinct from 'string' or
  p_value->>'storage_path' <> p_company_id::text || '/' || p_table_id::text || '/' || p_version::text || '/' || (p_value->>'document_hash') || '.pdf' or
  jsonb_typeof(p_value->'source_url') is distinct from 'string' or (p_value->>'source_url') !~ '^https://[^/[:space:]]+' or length(p_value->>'source_url')>2048 or
  jsonb_typeof(p_value->'publisher') is distinct from 'string' or length(trim(p_value->>'publisher')) not between 1 and 200 or
  jsonb_typeof(p_value->'file_name') is distinct from 'string' or length(p_value->>'file_name') not between 5 and 200 or
  (p_value->>'file_name') !~* '^[^/\\]+\.pdf$' then
  raise exception 'exact document identity/source required' using errcode='22023';
 end if;
end $$;

create function income_tax_private.table_state(p_doc income_tax_private.documents)
returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('table_id',p_doc.table_id,'version',p_doc.version,'value',p_doc.value,
  'registered_by',p_doc.registered_by,'registered_at',p_doc.registered_at,
  'official_document_verified',exists(select 1 from income_tax_private.verifications v where v.company_id=p_doc.company_id and v.table_id=p_doc.table_id and v.metadata_version=p_doc.version and v.document_hash=p_doc.value->>'document_hash' and v.storage_path=p_doc.value->>'storage_path'),
  'calculation_rules_verified',exists(select 1 from income_tax_private.verifications v where v.company_id=p_doc.company_id and v.table_id=p_doc.table_id and v.metadata_version=p_doc.version and v.document_hash=p_doc.value->>'document_hash' and v.storage_path=p_doc.value->>'storage_path' and v.calculation_rules_hash is not null),
  'common_data_approved',false);
$$;

create function income_tax_private.register_document(p_company_id uuid,p_table_id uuid,p_expected_version bigint,p_value jsonb,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before income_tax_private.documents%rowtype; v_after income_tax_private.documents%rowtype;
 v_version bigint; v_at timestamptz;
begin
 perform income_tax_private.require_admin(p_company_id);
 if p_table_id is null or p_expected_version is null or p_expected_version<0 or p_confirmed is distinct from true then
  raise exception 'explicit metadata confirmation required' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':income-tax-registry',0));
 select * into v_before from income_tax_private.documents where company_id=p_company_id and table_id=p_table_id for update;
 if coalesce(v_before.version,0)<>p_expected_version then raise exception 'income tax metadata version conflict' using errcode='40001'; end if;
 v_version := p_expected_version+1;
 perform income_tax_private.validate_metadata(p_company_id,p_table_id,v_version,p_value);
 if v_before.version is not null and
  (v_before.value->>'calendar_year' <> p_value->>'calendar_year' or v_before.value->>'kind' <> p_value->>'kind') then
  raise exception 'existing tax table calendar year and kind are immutable; register a new table ID' using errcode='22023';
 end if;
 if exists(select 1 from income_tax_private.documents d where d.company_id=p_company_id and d.table_id<>p_table_id and
  d.value->>'kind'=p_value->>'kind' and (d.value->>'starts_on')::date<(p_value->>'ends_before')::date and
  (p_value->>'starts_on')::date<(d.value->>'ends_before')::date) then
  raise exception 'income tax schedule overlap' using errcode='22023';
 end if;
 v_at := clock_timestamp();
 insert into income_tax_private.documents(company_id,table_id,version,value,registered_by,registered_at)
 values(p_company_id,p_table_id,v_version,p_value,auth.uid(),v_at)
 on conflict(company_id,table_id) do update set version=excluded.version,value=excluded.value,registered_by=excluded.registered_by,registered_at=excluded.registered_at
 returning * into v_after;
 insert into income_tax_private.history(company_id,table_id,version,event_type,before_value,after_value,actor_id,changed_at)
 values(p_company_id,p_table_id,v_version,'registration',v_before.value,p_value,auth.uid(),v_at);
 return income_tax_private.table_state(v_after);
end $$;

-- Trusted-side verification changes are audited too; no client EXECUTE grant.
create function income_tax_private.audit_verification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  insert into income_tax_private.history(company_id,table_id,version,event_type,before_value,after_value,actor_id,changed_at)
  values(old.company_id,old.table_id,old.metadata_version,'verification',to_jsonb(old),null,coalesce(auth.uid(),old.official_verified_by),clock_timestamp());
  return old;
 end if;
 insert into income_tax_private.history(company_id,table_id,version,event_type,before_value,after_value,actor_id,changed_at)
 values(new.company_id,new.table_id,new.metadata_version,'verification',case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new),coalesce(auth.uid(),new.calculation_verified_by,new.official_verified_by),clock_timestamp());
 return new;
end $$;
create trigger income_tax_verification_audit after insert or update or delete on income_tax_private.verifications
 for each row execute function income_tax_private.audit_verification();

create function income_tax_private.read_documents(p_company_id uuid,p_payroll_date text,p_kind text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_date date; v_tables jsonb; v_selected jsonb; v_history jsonb;
begin
 perform income_tax_private.require_admin(p_company_id);
 if p_payroll_date is null or p_payroll_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or p_kind is null or p_kind not in ('monthly','daily','bonus','computer_calculation') then
  raise exception 'explicit civil payroll date and table kind required' using errcode='22023';
 end if;
 v_date := p_payroll_date::date;
 select coalesce(jsonb_agg(income_tax_private.table_state(d) order by (d.value->>'calendar_year')::integer desc,d.table_id),'[]'::jsonb)
 into v_tables from income_tax_private.documents d where d.company_id=p_company_id;
 select income_tax_private.table_state(d) into v_selected from income_tax_private.documents d
 join income_tax_private.verifications v on v.company_id=d.company_id and v.table_id=d.table_id and v.metadata_version=d.version
  and v.document_hash=d.value->>'document_hash' and v.storage_path=d.value->>'storage_path'
 where d.company_id=p_company_id and d.value->>'kind'=p_kind and (d.value->>'calendar_year')::integer=extract(year from v_date)::integer
 and (d.value->>'starts_on')::date<=v_date and v_date<(d.value->>'ends_before')::date and v.calculation_rules_hash is not null;
 select coalesce(jsonb_agg(to_jsonb(h)-'company_id' order by h.event_id desc),'[]'::jsonb)
 into v_history from (select * from income_tax_private.history where company_id=p_company_id order by event_id desc limit 100) h;
 return jsonb_build_object('tables',v_tables,'selected',v_selected,'history',v_history);
end $$;

create function public.register_company_income_tax_table(p_company_id uuid,p_table_id uuid,p_expected_version bigint,p_value jsonb,p_confirmed boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select income_tax_private.register_document(p_company_id,p_table_id,p_expected_version,p_value,p_confirmed);
$$;
create function public.read_company_income_tax_tables(p_company_id uuid,p_payroll_date text,p_kind text)
returns jsonb language sql security invoker set search_path='' as $$
 select income_tax_private.read_documents(p_company_id,p_payroll_date,p_kind);
$$;
revoke all on all functions in schema income_tax_private from public,anon,authenticated;
grant execute on function income_tax_private.register_document(uuid,uuid,bigint,jsonb,boolean),income_tax_private.read_documents(uuid,text,text) to authenticated;
revoke all on function public.register_company_income_tax_table(uuid,uuid,bigint,jsonb,boolean),public.read_company_income_tax_tables(uuid,text,text) from public,anon,authenticated;
grant execute on function public.register_company_income_tax_table(uuid,uuid,bigint,jsonb,boolean),public.read_company_income_tax_tables(uuid,text,text) to authenticated;
