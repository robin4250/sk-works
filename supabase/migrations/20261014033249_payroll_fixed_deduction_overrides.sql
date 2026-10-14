-- CLI-generated. Explicit monthly manual corrections use the existing
-- authenticated, versioned tax-conditions RPC and audit history.
begin;
do $guard$ begin
 if (select md5(prosrc) from pg_proc where oid='payroll_tax_private.validate_conditions(jsonb)'::regprocedure)<>'b6c6f4827cf82d699a5e479dc63e8337' then
  raise exception 'Payroll condition validator differs; inspect before applying';end if;
 if (select md5(prosrc) from pg_proc where oid='payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)'::regprocedure)<>'b939396fc7fce29b3abfe9805a01223b' then
  raise exception 'Payroll tax calculator differs; inspect before applying';end if;
end $guard$;
CREATE OR REPLACE FUNCTION payroll_tax_private.validate_conditions(v jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare k text; d date; entry record;
begin
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
end $function$
;
CREATE OR REPLACE FUNCTION payroll_tax_private.calculate(cid uuid, wid uuid, p_start date, p_end date, p_gross bigint, p_legacy_deductions bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare profile payroll_tax_private.worker_conditions%rowtype; v jsonb; settings jsonb;
 payday date; additions bigint; gross bigint; social bigint; income bigint; legacy_social bigint; legacy_income bigint;
 premiums jsonb:='{}'; evidence jsonb:='[]'; item jsonb; val jsonb; kind text; flag text; label text;
 base bigint; premium integer; insured_month date; birth date; age_start date; age_end date;
 deduction bigint; taxable bigint; month_offset integer; expected_payment date;
 health_raw numeric:=0; health_rounded integer:=0; health_month date;
 automatic_premiums jsonb; automatic_income bigint; override_entry record; override_label text;
begin
 select * into profile from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid and starts_on<=p_start order by starts_on desc limit 1;
 if not found then return null;end if;
 v:=profile.value;perform payroll_tax_private.validate_conditions(v);
 if p_start<>date_trunc('month',p_start)::date or p_end<>(p_start+interval '1 month - 1 day')::date then raise exception '税自動計算は月次給与を対象とします' using errcode='22023';end if;
 select to_jsonb(s) into settings from public.worker_payroll_settings s where company_id=cid and worker_id=wid;
 if settings is null then raise exception '個別給与設定がありません' using errcode='22023';end if;
 settings:=payroll_unit_private.augment_settings(cid,wid,p_start,p_end,settings);
 legacy_social:=round(coalesce((settings->>'social_insurance_monthly')::numeric,0));
 legacy_income:=round(coalesce((settings->>'income_tax_monthly')::numeric,0));
 payday:=private.payroll_payment_date(p_end,cid,'{}'::jsonb);
 select coalesce(sum(amount_yen) filter(where direction='addition'),0) into additions from public.payroll_adjustments
 where company_id=cid and worker_id=wid and effective_date between p_start and p_end and cancelled_at is null;
 gross:=p_gross+additions;
 if gross<0 or (v->>'income_mode'<>'fixed' and (v->>'non_taxable_yen')::bigint>gross) or (v->>'insurance_mode'='rates' and (v->>'employment')::boolean and (v->>'employment_excluded_yen')::bigint>gross) then
  raise exception '非課税額・雇用保険対象外額が支給額を超えています' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(settings->'custom_deductions','[]')) x where coalesce((x->>'amount_yen')::numeric,0)<>0 and (
 (v->>'insurance_mode'='rates' and trim(x->>'name') in ('健康保険','健康保険料','社会保険','社会保険料','介護保険','介護保険料','厚生年金','厚生年金保険','厚生年金保険料','雇用保険','雇用保険料','子ども・子育て支援金')) or
 (v->>'income_mode'<>'fixed' and trim(x->>'name')='所得税'))) then
 raise exception '自由控除に同じ税・保険料があります。二重控除を避けるため確認してください' using errcode='22023';end if;
 if exists(select 1 from public.payroll_adjustments a where a.company_id=cid and a.worker_id=wid and a.effective_date between p_start and p_end and a.cancelled_at is null and a.amount_yen<>0 and (
  (v->>'insurance_mode'='rates' and trim(a.label_snapshot) in ('健康保険','健康保険料','社会保険','社会保険料','介護保険','介護保険料','厚生年金','厚生年金保険','厚生年金保険料','雇用保険','雇用保険料','子ども・子育て支援金')) or
  (v->>'income_mode'<>'fixed' and trim(a.label_snapshot)='所得税'))) then
  raise exception '給与調整に同じ税・保険料があります。二重計上を避けるため確認してください' using errcode='22023';end if;
 social:=legacy_social;
 if v->>'insurance_mode'='rates' then
  social:=0;
  foreach kind in array array['health_insurance','nursing_insurance','pension_insurance','employment_insurance','child_support'] loop
   flag:=case kind when 'health_insurance' then 'health' when 'nursing_insurance' then 'nursing' when 'pension_insurance' then 'pension' when 'employment_insurance' then 'employment' else 'child_support' end;
   label:=case kind when 'health_insurance' then '健康保険料' when 'nursing_insurance' then '介護保険料' when 'pension_insurance' then '厚生年金保険' when 'employment_insurance' then '雇用保険料' else '子ども・子育て支援金' end;
   premium:=0;
   if (v->>flag)::boolean then
    item:=payroll_tax_private.rate_for_month(cid,kind,p_start);
    if item is null then raise exception '適用月の料率が未設定です: %',label using errcode='22023';end if;
    val:=item->'value';perform payroll_rate_private.validate_value(val);
    month_offset:=(extract(year from (val->>'insurance_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'insurance_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    insured_month:=(p_start+make_interval(months=>month_offset))::date;
    month_offset:=(extract(year from (val->>'payment_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'payment_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    expected_payment:=(p_start+make_interval(months=>month_offset))::date;
    if expected_payment<>date_trunc('month',payday)::date then raise exception '料率の支払月と会社の給与支払月が一致しません: %',label using errcode='22023';end if;
    base:=case kind when 'pension_insurance' then (v->>'pension_base_yen')::bigint when 'employment_insurance' then gross-(v->>'employment_excluded_yen')::bigint else (v->>'health_base_yen')::bigint end;
    if kind='nursing_insurance' then
     birth:=(v->>'birth_date')::date;
     age_start:=date_trunc('month',birth+interval '40 years'-interval '1 day')::date;
     age_end:=date_trunc('month',birth+interval '65 years'-interval '1 day')::date;
     if insured_month<age_start or insured_month>=age_end then base:=0;end if;
    end if;
    if kind in ('health_insurance','nursing_insurance','child_support') then
     if health_month is not null and health_month<>insured_month then raise exception '健康保険・介護・支援金の適用月が一致しません' using errcode='22023';end if;
     health_month:=insured_month;
     health_raw:=health_raw+base::numeric*(val->>'employee')::bigint/100000000;
     premium:=greatest(ceil(health_raw-0.5),0)::integer-health_rounded;
     health_rounded:=health_rounded+premium;
    else
     premium:=payroll_tax_private.employee_premium(base,(val->>'employee')::bigint);
    end if;
    evidence:=evidence||jsonb_build_array(item||jsonb_build_object('insurance_month',insured_month,'base_yen',base,'employee_yen',premium));
   end if;
   social:=social+premium;premiums:=premiums||jsonb_build_object(label,premium);
  end loop;
 end if;
 automatic_premiums:=premiums;
 if v->>'insurance_mode'='rates' then
  for override_entry in select key,value from jsonb_each(coalesce(v->'deduction_overrides','{}')) where key<>'income_tax' loop
   override_label:=case override_entry.key
    when 'employment_insurance' then '雇用保険料'
    when 'health_insurance' then '健康保険料'
    when 'pension_insurance' then '厚生年金保険'
    when 'nursing_insurance' then '介護保険料' end;
   premiums:=jsonb_set(premiums,array[override_label],override_entry.value,true);
  end loop;
  select coalesce(sum(value::text::bigint),0) into social from jsonb_each(premiums);
 end if;
 taxable:=greatest(gross-(v->>'non_taxable_yen')::bigint-social-(v->>'additional_social_deduction_yen')::bigint,0);
 income:=legacy_income;
 if v->>'income_mode'<>'fixed' then income:=payroll_tax_private.monthly_income_tax(payday,taxable,v->>'income_mode',(v->>'dependents')::integer);end if;
 automatic_income:=income;
 if coalesce(v->'deduction_overrides','{}') ? 'income_tax' then
  income:=(v#>>'{deduction_overrides,income_tax}')::bigint;
 end if;
 deduction:=p_legacy_deductions-legacy_income-legacy_social+income+social;
 if deduction<0 then raise exception '控除合計が不整合です' using errcode='22023';end if;
 return jsonb_build_object('calculator_version','payroll-tax-20261014-overrides-v1','condition_version',profile.version,'conditions_start',profile.starts_on,'conditions',v,
 'payment_date',payday,'gross_with_adjustments',gross,'income_tax_base_yen',taxable,'income_tax_yen',income,'social_yen',social,'deductions',deduction,
 'automatic_premiums',automatic_premiums,'automatic_income_tax_yen',automatic_income,
 'deduction_overrides',coalesce(v->'deduction_overrides','{}'),'premiums',premiums,'rates',evidence,'income_table',case when v->>'income_mode'='fixed' then null else 'nta-monthly-2026-c583c9c3' end);
exception when sqlstate '22023' then
 return jsonb_build_object('calculator_version','payroll-tax-20261014-overrides-v1','blocked',true,'reason',sqlerrm,'deductions',p_legacy_deductions,'conditions_start',profile.starts_on,'condition_version',profile.version);
end $function$
;
-- No new table access; internal functions keep their existing execute grants.
create or replace function public.payroll_deduction_overrides_contract_version()
returns integer language sql stable security invoker set search_path='' as $$ select 1 $$;
revoke all on function public.payroll_deduction_overrides_contract_version() from public,anon;
grant execute on function public.payroll_deduction_overrides_contract_version() to authenticated;
commit;
