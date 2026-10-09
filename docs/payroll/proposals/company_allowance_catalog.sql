-- DESIGN PROPOSAL ONLY: not a migration, not deployed, no live callers.
-- Reuses company_rate_settings as the company source. No legacy backfill.
alter table public.company_rate_settings
 add column allowance_extra_catalog jsonb not null default '[]'::jsonb,
 add column allowance_catalog_version bigint not null default 0;
create schema if not exists payroll_allowance_private;
revoke all on schema payroll_allowance_private from public, anon, authenticated;
create table payroll_allowance_private.change_log (
 company_id uuid not null, catalog_version bigint not null,
 actor_id uuid not null, changed_at timestamptz not null default now(),
 before_catalog jsonb not null, after_catalog jsonb not null,
 primary key(company_id,catalog_version)
);
alter table payroll_allowance_private.change_log enable row level security;
revoke all on payroll_allowance_private.change_log from public, anon, authenticated;

-- Any legacy writer also advances the optimistic lock. No old RPC is altered.
create function payroll_allowance_private.advance_version() returns trigger
language plpgsql set search_path = '' as $$ begin
 new.allowance_catalog_version:=old.allowance_catalog_version+1; return new;
end $$;
revoke all on function payroll_allowance_private.advance_version() from public,anon,authenticated;
create trigger proposal_allowance_catalog_version before update on public.company_rate_settings
 for each row execute function payroll_allowance_private.advance_version();

-- Legacy slot IDs are deterministic company+slot identities, never name matching.
create function payroll_allowance_private.legacy_labels(p_company_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',md5(p_company_id::text||':legacy-allowance:'||slot)::uuid,
 'name',btrim(name),'unit',coalesce(nullif(btrim(unit),''),'回'),'active',true)),'[]'::jsonb)
 from public.company_rate_settings r cross join lateral (values
 ('1',r.allowance_1_name,r.allowance_1_unit),('2',r.allowance_2_name,r.allowance_2_unit),('3',r.allowance_3_name,r.allowance_3_unit)
 ) v(slot,name,unit) where r.company_id=p_company_id and nullif(btrim(name),'') is not null;
$$;
revoke all on function payroll_allowance_private.legacy_labels(uuid) from public,anon,authenticated;

create function public.proposal_read_company_allowance_labels(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_catalog jsonb; v_version bigint;
begin
 if auth.uid() is null or not exists (
  select 1 from public.company_members where user_id=auth.uid() and company_id=p_company_id
 ) then raise exception 'company membership required' using errcode='42501'; end if;
 select allowance_extra_catalog,allowance_catalog_version into v_catalog,v_version
 from public.company_rate_settings where company_id=p_company_id;
 v_catalog:=coalesce(v_catalog,'[]')||payroll_allowance_private.legacy_labels(p_company_id);
 return jsonb_build_object('version',coalesce(v_version,0),'items',coalesce((
  select jsonb_agg(jsonb_build_object('id',e->>'id','name',e->>'name','unit',e->>'unit','active',e->'active') order by e->>'id')
  from jsonb_array_elements(coalesce(v_catalog,'[]')) e where (e->>'active')::boolean
 ),'[]'::jsonb));
end $$;

create function public.proposal_save_company_allowance_item(
 p_company_id uuid,p_id uuid,p_expected_version bigint,p_name text,p_unit text,p_amount_yen bigint,p_active boolean
) returns bigint language plpgsql security definer set search_path = '' as $$
declare v_before jsonb; v_after jsonb; v_version bigint; v_item jsonb;
begin
 if auth.uid() is null or not exists (
  select 1 from public.company_members where user_id=auth.uid() and company_id=p_company_id and role::text in ('owner','admin')
 ) then raise exception 'owner or admin permission required' using errcode='42501'; end if;
 if p_id is null or p_expected_version is null or p_name is null or btrim(p_name)='' or length(btrim(p_name))>80
 or p_unit not in ('回','有無') or p_unit is null or p_amount_yen is null or p_amount_yen<0 or p_active is null then
  raise exception 'invalid allowance fields' using errcode='22023'; end if;
 -- The existing company settings row must exist. Never create implicit defaults.
 select allowance_extra_catalog,allowance_catalog_version into v_before,v_version
 from public.company_rate_settings where company_id=p_company_id for update;
 if not found then raise exception 'company settings missing' using errcode='22023'; end if;
 if v_version<>p_expected_version then raise exception 'catalog version conflict' using errcode='40001'; end if;
 if exists(select 1 from generate_series(1,3) slot where p_id=md5(p_company_id::text||':legacy-allowance:'||slot)::uuid) then raise exception 'legacy slot must use existing company settings' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(v_before||payroll_allowance_private.legacy_labels(p_company_id)) e where e->>'id'<>p_id::text and lower(btrim(e->>'name'))=lower(btrim(p_name))) then
  raise exception 'duplicate allowance name' using errcode='23505'; end if;
 v_item:=jsonb_build_object('id',p_id,'name',btrim(p_name),'unit',p_unit,'amount_yen',p_amount_yen,'active',p_active);
 select coalesce(jsonb_agg(e order by e->>'id'),'[]'::jsonb) into v_after
 from jsonb_array_elements(v_before) e where e->>'id'<>p_id::text;
 v_after:=v_after||jsonb_build_array(v_item);
 update public.company_rate_settings set allowance_extra_catalog=v_after
 where company_id=p_company_id;
 insert into payroll_allowance_private.change_log(company_id,catalog_version,actor_id,before_catalog,after_catalog)
 values(p_company_id,v_version+1,auth.uid(),v_before,v_after);
 return v_version+1;
end $$;
revoke all on function public.proposal_read_company_allowance_labels(uuid) from public,anon;
revoke all on function public.proposal_save_company_allowance_item(uuid,uuid,bigint,text,text,bigint,boolean) from public,anon;
grant execute on function public.proposal_read_company_allowance_labels(uuid) to authenticated;
grant execute on function public.proposal_save_company_allowance_item(uuid,uuid,bigint,text,text,bigint,boolean) to authenticated;
