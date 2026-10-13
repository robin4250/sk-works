-- First-use defaults only. Existing company settings always win, including races.
create function payroll_rate_private.initialize_official_rates(
 p_company_id uuid, p_scope_version bigint, p_candidates jsonb, p_fallback boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_kind text; v_value jsonb; v_defaults jsonb; v_candidate payroll_rate_private.candidates%rowtype;
 v_month date := date_trunc('month', clock_timestamp() at time zone 'Asia/Tokyo')::date;
 v_kinds text[] := array['health_insurance','nursing_insurance','pension_insurance','employment_insurance'];
begin
 perform payroll_rate_private.require_admin(p_company_id);
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':payroll-rate-registry',0));
 if exists(select 1 from payroll_rate_private.settings where company_id=p_company_id) then
  return jsonb_build_object('initialized',false);
 end if;
 if p_scope_version is null or not exists(select 1 from payroll_rate_private.company_scope
   where company_id=p_company_id and version=p_scope_version and value->>'insurer'='kyokai') then
  raise exception 'initial rate scope changed or unsupported' using errcode='40001';
 end if;
 if p_fallback is true then
  -- User-approved reference values. Never label these as verified official data.
  v_defaults := '{"health_insurance":{"label":"健康保険料率","total":9900000,"employee":4950000,"employer":4950000},"nursing_insurance":{"label":"介護保険料率","total":1620000,"employee":810000,"employer":810000},"pension_insurance":{"label":"厚生年金保険料率","total":18300000,"employee":9150000,"employer":9150000},"employment_insurance":{"label":"雇用保険料率","total":1650000,"employee":600000,"employer":1050000}}'::jsonb;
  foreach v_kind in array v_kinds loop
   v_value := (v_defaults->v_kind) || jsonb_build_object('kind',v_kind,
    'insurance_month',v_month::text,'payroll_month',v_month::text,
    'payment_month',(v_month+interval '1 month')::date::text,
    'source',jsonb_build_object('url','https://github.com/robin4250/sk-works/issues/273',
     'publisher','SKO初期参考値（最新未確認）','document_hash','initial-reference-2026-10',
     'applicability',jsonb_build_object('initial_reference','2026-10',
      'verification','最新未確認','scope_version',p_scope_version::text)));
   perform payroll_rate_private.write_rate(p_company_id,v_kind,0,v_value,true,null);
  end loop;
  return jsonb_build_object('initialized',true,'fallback',true);
 end if;
 if p_fallback is distinct from false then
  raise exception 'initialization mode required' using errcode='22023';
 end if;
 if p_candidates is null or jsonb_typeof(p_candidates) is distinct from 'object' then
  raise exception 'four initial candidates required' using errcode='22023';
 end if;
 if (select count(*) from jsonb_object_keys(p_candidates))<>4 or not p_candidates ?& v_kinds then
  raise exception 'four initial candidates required' using errcode='22023';
 end if;
 foreach v_kind in array v_kinds loop
  select * into v_candidate from payroll_rate_private.candidates
   where company_id=p_company_id and item_id=v_kind and candidate_id=(p_candidates->>v_kind)::uuid for share;
  if not found or v_candidate.scope_version<>p_scope_version
   or v_candidate.verified_by is distinct from auth.uid()
   or v_candidate.verified_at is null
   or v_candidate.checked_at < clock_timestamp()-interval '10 minutes'
   or v_candidate.checked_at > clock_timestamp()
   or v_candidate.value->>'insurance_month' is distinct from v_month::text
   or v_candidate.value->>'payroll_month' is distinct from v_month::text
   or v_candidate.value->>'payment_month' is distinct from (v_month+interval '1 month')::date::text then
   raise exception 'fresh current-month official candidate required' using errcode='22023';
  end if;
  -- All four writes and their normal audit records commit together or roll back.
  perform payroll_rate_private.write_rate(p_company_id,v_kind,0,null,true,v_candidate.candidate_id);
 end loop;
 return jsonb_build_object('initialized',true,'fallback',false);
end $$;
create function public.initialize_official_company_rates(p_company_id uuid,p_scope_version bigint,p_candidates jsonb,p_fallback boolean)
returns jsonb language sql security invoker set search_path='' as $$
 select payroll_rate_private.initialize_official_rates(p_company_id,p_scope_version,p_candidates,p_fallback);
$$;
revoke all on function payroll_rate_private.initialize_official_rates(uuid,bigint,jsonb,boolean),public.initialize_official_company_rates(uuid,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function payroll_rate_private.initialize_official_rates(uuid,bigint,jsonb,boolean),public.initialize_official_company_rates(uuid,bigint,jsonb,boolean) to authenticated;
