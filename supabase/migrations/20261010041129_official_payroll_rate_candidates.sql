-- Trusted publication only: never applies a rate or refreshes payroll.
-- The Edge Function authenticates the human caller and fetches allowlisted sources.
-- Recheck live membership, deletion restriction and scope after that network round trip.
create function public.publish_official_payroll_rate_candidates(
 p_company_id uuid,p_actor_id uuid,p_scope_version bigint,p_values jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_scope jsonb; v_version bigint; v_value jsonb; v_kind text; v_url text;
 v_app jsonb; v_seen text[] := '{}'::text[]; v_at timestamptz;
begin
 perform 1 from public.companies where id=p_company_id for key share;
 if not found or p_actor_id is null then
  raise exception 'official rate publisher access denied' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':payroll-rate-registry',0));
 if not exists(select 1 from public.company_members
    where company_id=p_company_id and user_id=p_actor_id and role::text in ('owner','admin'))
   or exists(select 1 from private.account_deletion_access_restrictions where user_id=p_actor_id) then
  raise exception 'official rate publisher access denied' using errcode='42501';
 end if;
 select value,version into v_scope,v_version from payroll_rate_private.company_scope
  where company_id=p_company_id for share;
 if p_scope_version is null or v_version is null or v_version<>p_scope_version then
  raise exception 'official rate company scope version conflict' using errcode='40001';
 end if;
 if p_values is null or jsonb_typeof(p_values) is distinct from 'array' then
  raise exception 'official rate batch must be an array' using errcode='22023';
 end if;
 if jsonb_array_length(p_values) not between 1 and 5 or octet_length(p_values::text)>163840 then
  raise exception 'official rate batch must contain 1 to 5 values' using errcode='22023';
 end if;
 v_at := clock_timestamp();
 for v_value in select value from jsonb_array_elements(p_values) loop
  perform payroll_rate_private.validate_value(v_value);
  v_kind := v_value->>'kind'; v_url := v_value#>>'{source,url}';
  v_app := v_value#>'{source,applicability}';
  if v_kind not in ('health_insurance','nursing_insurance','pension_insurance','employment_insurance','child_support')
    or v_kind=any(v_seen) then
   raise exception 'unsupported or duplicate official rate kind' using errcode='22023';
  end if;
  v_seen := array_append(v_seen,v_kind);
  if (v_value#>>'{source,document_hash}') !~ '^[0-9a-f]{64}$'
    or v_app->>'scope_version' is distinct from p_scope_version::text then
   raise exception 'official source hash or scope evidence invalid' using errcode='22023';
  end if;
  if v_kind in ('health_insurance','nursing_insurance','child_support') and
    (v_scope->>'insurer' is distinct from 'kyokai' or v_app->>'insurer' is distinct from 'kyokai') then
   raise exception 'official rate insurer scope differs' using errcode='22023';
  end if;
  if v_kind='health_insurance' and
    (v_scope->>'prefecture' is null or v_app->>'prefecture' is distinct from v_scope->>'prefecture') then
   raise exception 'official rate prefecture differs' using errcode='22023';
  end if;
  if v_kind='employment_insurance' and
    (v_scope->>'employment_business' is null or v_app->>'employment_business' is distinct from v_scope->>'employment_business') then
   raise exception 'official rate employment business differs' using errcode='22023';
  end if;
  if not (case v_kind
   when 'health_insurance' then v_url ~ '^https://www\.kyoukaikenpo\.or\.jp/about/business/insurance_rate/rate_prefectures/r[0-9]{2}/$'
   when 'nursing_insurance' then v_url='https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/002/'
   when 'child_support' then v_url='https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/003/'
   when 'pension_insurance' then v_url='https://www.nenkin.go.jp/service/kounen/hokenryo/ryogaku/ryogakuhyo/index.html'
   when 'employment_insurance' then v_url='https://jsite.mhlw.go.jp/yamagata-roudoukyoku/koyouhoken-20260316.html'
   else false end) then
   raise exception 'official rate source URL is not allowlisted for kind' using errcode='22023';
  end if;
  if coalesce(v_app->>'effective_insurance_month','') !~ '^[0-9]{4}-(0[1-9]|1[0-2])-01$' then
   raise exception 'official effective insurance month required' using errcode='22023';
  end if;
  if (v_value->>'insurance_month')::date < (v_app->>'effective_insurance_month')::date then
   raise exception 'company insurance month precedes official effective month' using errcode='22023';
  end if;
  -- Keep past candidates and evidence; selection/apply is a separate user action.
  insert into payroll_rate_private.candidates(company_id,candidate_id,item_id,value,
   checked_at,scope_version,verified_at,verified_by,verification_evidence)
  values(p_company_id,gen_random_uuid(),v_kind,v_value,v_at,p_scope_version,v_at,p_actor_id,
   'official-rate-parser-v1; sha256=' || (v_value#>>'{source,document_hash}'));
 end loop;
 return jsonb_build_object('count',cardinality(v_seen));
end $$;
revoke all on function public.publish_official_payroll_rate_candidates(uuid,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.publish_official_payroll_rate_candidates(uuid,uuid,bigint,jsonb) to service_role;
