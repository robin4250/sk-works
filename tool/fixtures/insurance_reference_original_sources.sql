CREATE OR REPLACE FUNCTION payroll_tax_private.read_conditions(cid uuid, wid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare items jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) or not coalesce(private.payroll_settings_allowed(cid,wid,'view'),false) then
  raise exception 'payroll access denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('starts_on',starts_on,'version',version,'value',value) order by starts_on desc),'[]') into items
 from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid;
 return jsonb_build_object('manual_insurance_contract_version',1,'company_id',cid,'worker_id',wid,'can_edit',coalesce(private.payroll_settings_allowed(cid,wid,'edit'),false),'items',items,'supported_income_years',jsonb_build_array(2026));
end $function$;

CREATE OR REPLACE FUNCTION payroll_tax_private.save_conditions(cid uuid, wid uuid, p_start date, p_expected_version bigint, p_value jsonb, p_confirmed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare old_value payroll_tax_private.worker_conditions%rowtype; r record; stamp timestamptz:=clock_timestamp();
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) or not coalesce(private.payroll_settings_allowed(cid,wid,'edit'),false) then
  raise exception 'payroll access denied' using errcode='42501';end if;
 if p_confirmed is not true or p_expected_version is null or p_expected_version<0 or p_start is null or p_start<>date_trunc('month',p_start)::date then
  raise exception '適用月と計算条件の確認が必要です' using errcode='22023';end if;
 perform payroll_tax_private.validate_conditions(p_value);
 -- Same ordering as payroll refresh/finalization. No writes to finalized documents.
 perform 1 from public.companies where id=cid for share;
 perform 1 from public.workers where id=wid and company_id=cid for update;
 if not found then raise exception 'payroll access denied' using errcode='42501';end if;
 select * into old_value from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid and starts_on=p_start for update;
 if old_value.version=p_expected_version+1 and old_value.value=p_value then return payroll_tax_private.read_conditions(cid,wid);end if;
 if coalesce(old_value.version,0)<>p_expected_version then raise exception '計算条件が更新されています。再読み込みしてください' using errcode='40001';end if;
 insert into payroll_tax_private.worker_conditions values(cid,wid,p_start,p_expected_version+1,p_value,auth.uid(),stamp)
 on conflict(company_id,worker_id,starts_on) do update set version=excluded.version,value=excluded.value,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 insert into payroll_tax_private.condition_history values(cid,wid,p_start,p_expected_version+1,old_value.value,p_value,auth.uid(),stamp);
 for r in select period_start from public.payroll_statements where company_id=cid and worker_id=wid and period_start>=p_start and workflow_state='draft' and automatic_calculation order by period_start loop
  perform private.refresh_automatic_payroll(cid,wid,r.period_start);
  perform private.sync_payroll_attendance_detail(cid,wid,r.period_start);
  if exists(select 1 from public.payroll_statements where company_id=cid and worker_id=wid and period_start=r.period_start and detail#>>'{tax_calculation,blocked}'='true') then
   raise exception '税計算に必要な料率・対象年・支給条件を確認してください' using errcode='22023';end if;
 end loop;
 return payroll_tax_private.read_conditions(cid,wid);
end $function$;

CREATE OR REPLACE FUNCTION payroll_tax_private.validate_conditions(v jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare k text; d date; entry record; manual_total bigint:=0;
begin
 if v->>'insurance_mode'='manual' then
  if jsonb_typeof(v) IS DISTINCT FROM 'object' OR octet_length(v::text)>4096
  OR v-array['insurance_mode','manual_insurance_premiums','income_mode','dependents','non_taxable_yen','additional_social_deduction_yen','deduction_overrides']<>'{}'::jsonb
  OR coalesce(v->>'income_mode','') NOT IN ('fixed','koh','otsu')
  THEN RAISE EXCEPTION '個別保険月額の条件を確認してください' USING errcode='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['dependents','non_taxable_yen','additional_social_deduction_yen'] LOOP
   IF jsonb_typeof(v->k) IS DISTINCT FROM 'number' OR (v->>k)!~'^[0-9]{1,9}$'
   THEN RAISE EXCEPTION '金額・人数は整数で入力してください' USING errcode='22023'; END IF;
  END LOOP;
  IF (v->>'dependents')::integer>99 THEN RAISE EXCEPTION '扶養人数を確認してください' USING errcode='22023'; END IF;
  IF jsonb_typeof(v->'manual_insurance_premiums') IS DISTINCT FROM 'object'
  OR (v->'manual_insurance_premiums')-ARRAY['health_insurance','pension_insurance','employment_insurance','nursing_insurance','child_support']<>'{}'::jsonb
  THEN RAISE EXCEPTION '保険別の個別月額を確認してください' USING errcode='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['health_insurance','pension_insurance','employment_insurance','nursing_insurance','child_support'] LOOP
   IF jsonb_typeof(v->'manual_insurance_premiums'->k) IS DISTINCT FROM 'number'
   OR (v->'manual_insurance_premiums'->>k)!~'^[0-9]{1,10}$'
   OR (v->'manual_insurance_premiums'->>k)::numeric>2147483647
   THEN RAISE EXCEPTION '各保険料は本人負担月額を入力してください。該当なしは0円を明示してください' USING errcode='22023'; END IF;
   manual_total:=manual_total+(v->'manual_insurance_premiums'->>k)::bigint;
  END LOOP;
  IF manual_total>2147483647 THEN RAISE EXCEPTION '保険料合計が上限を超えています' USING errcode='22023'; END IF;
  IF v?'deduction_overrides' THEN
   IF jsonb_typeof(v->'deduction_overrides') IS DISTINCT FROM 'object' OR (v->'deduction_overrides')-ARRAY['income_tax']<>'{}'::jsonb
   THEN RAISE EXCEPTION '個別保険月額と自動計算修正を混在できません' USING errcode='22023'; END IF;
   IF v->'deduction_overrides'?'income_tax' AND (jsonb_typeof(v#>'{deduction_overrides,income_tax}') IS DISTINCT FROM 'number'
   OR (v#>>'{deduction_overrides,income_tax}')!~'^[0-9]{1,10}$' OR (v#>>'{deduction_overrides,income_tax}')::numeric>2147483647)
   THEN RAISE EXCEPTION '所得税の修正額を確認してください' USING errcode='22023'; END IF;
  END IF;
  RETURN;
 end if;
 if v is null or jsonb_typeof(v)<>'object' or octet_length(v::text)>4096 or
 v-array['insurance_mode','health','pension','employment','child_support','nursing','birth_date','health_base_yen','pension_base_yen','income_mode','dependents','non_taxable_yen','employment_excluded_yen','additional_social_deduction_yen','deduction_overrides']<>'{}'::jsonb then
  raise exception '税計算条件が不正です' using errcode='22023';end if;
 if coalesce(v->>'insurance_mode','') not in ('fixed','rates') or coalesce(v->>'income_mode','') not in ('fixed','koh','otsu') then
  raise exception '計算方式を選択してください' using errcode='22023';end if;
 foreach k in array array['health','pension','employment','child_support','nursing'] loop
  if jsonb_typeof(v->k) is distinct from 'boolean' then raise exception '加入条件を確認してください' using errcode='22023';end if;
 end loop;
 foreach k in array array['health_base_yen','pension_base_yen','dependents','non_taxable_yen','employment_excluded_yen','additional_social_deduction_yen'] loop
  if jsonb_typeof(v->k) is distinct from 'number' or (v->>k)!~'^[0-9]{1,9}$' then raise exception '金額・人数は整数で入力してください' using errcode='22023';end if;
 end loop;
 if (v->>'dependents')::integer>99 then raise exception '扶養人数を確認してください' using errcode='22023';end if;
 if v->>'insurance_mode'='rates' then
  if ((v->>'nursing')::boolean or (v->>'child_support')::boolean) and not (v->>'health')::boolean then raise exception '介護保険・支援金の健康保険加入条件を確認してください' using errcode='22023';end if;
  if ((v->>'health')::boolean or (v->>'nursing')::boolean or (v->>'child_support')::boolean) and (v->>'health_base_yen')::integer<=0 then
   raise exception '健康保険の標準報酬月額が必要です' using errcode='22023';end if;
  if (v->>'pension')::boolean and (v->>'pension_base_yen')::integer<=0 then raise exception '厚生年金の標準報酬月額が必要です' using errcode='22023';end if;
  if (v->>'nursing')::boolean then
   if coalesce(v->>'birth_date','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception '介護保険の年齢判定には生年月日が必要です' using errcode='22023';end if;
   d:=(v->>'birth_date')::date;
  end if;
 end if;
 if v->'birth_date' is not null and v->'birth_date'<>'null'::jsonb then
  d:=(v->>'birth_date')::date;
  if d<date '1900-01-01' then raise exception '生年月日を確認してください' using errcode='22023';end if;
 end if;
 if v ? 'deduction_overrides' then
  if jsonb_typeof(v->'deduction_overrides') is distinct from 'object'
    or (v->'deduction_overrides')-array['income_tax','employment_insurance','health_insurance','pension_insurance','nursing_insurance']<>'{}'::jsonb then
   raise exception '控除の手入力修正が不正です' using errcode='22023';
  end if;
  for entry in select key,value from jsonb_each(v->'deduction_overrides') loop
   if jsonb_typeof(entry.value) is distinct from 'number'
     or entry.value::text !~ '^[0-9]{1,10}$'
     or entry.value::text::numeric > 2147483647 then
    raise exception '控除の修正額は0以上の整数で入力してください' using errcode='22023';
   end if;
   if entry.key<>'income_tax' and v->>'insurance_mode'<>'rates' then
    raise exception '保険料の個別修正には個別の自動計算条件が必要です' using errcode='22023';
   end if;
  end loop;
 end if;
end $function$;