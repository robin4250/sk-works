\set ON_ERROR_STOP on
-- Disposable database, synthetic snapshots; not a company/auth integration proof.
create role anon;
create role authenticated;
create role service_role;
\i docs/candidates/company_checkout_receipt_core.sql.review-only
do $proof$
declare day_item jsonb:=jsonb_build_object('origin','company_common','id','00000000-0000-0000-0000-000000000001','name','合成日手当','section','earning','unit','day','rate_yen',2500);
 r1 jsonb;r2 jsonb;answer jsonb;original jsonb;checks integer:=0;
begin
 r1:=jsonb_build_object('contract_version',1,'work_date','2026-10-20','items',jsonb_build_array(day_item));
 r2:=jsonb_build_object('contract_version',1,'work_date','2026-10-21','items',jsonb_build_array(day_item));
 answer:=company_checkout_allowance_private.aggregate('[]');
 if answer->'items'<>'[]'::jsonb or (answer->>'blocked')::boolean then raise exception 'empty receipt behavior';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(r1,r1));
 if answer#>>'{items,0,quantity}'<>'1' or answer#>>'{items,0,amount_yen}'<>'2500' or (answer->>'blocked')::boolean then raise exception 'same-day route/site/retry duplication';end if;checks:=checks+1;
 original:=answer;
 if company_checkout_allowance_private.aggregate(jsonb_build_array(r1,r1)) is distinct from original then raise exception 'pure retry differs';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(r1,r2));
 if answer#>>'{items,0,quantity}'<>'2' or answer#>>'{earnings,0,amount_yen}'<>'5000' then raise exception 'two actual selected days';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(r1,jsonb_set(r1,'{items,0,rate_yen}','3000')));
 if (answer->>'blocked')::boolean is not true or answer#>>'{reasons,0,code}'<>'same_day_registration_conflict' then raise exception 'conflicting same-day rate must block';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(r1,jsonb_set(r2,'{items,0,rate_yen}','3000')));
 if jsonb_array_length(answer->'items')<>2 or (answer->>'blocked')::boolean then raise exception 'distinct dated snapshot rates lost';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(jsonb_set(r1,'{items,0,section}','"deduction"')));
 if answer->'earnings'<>'[]'::jsonb or answer#>>'{deductions,0,amount_yen}'<>'2500' then raise exception 'deduction direction';end if;checks:=checks+1;
 answer:=company_checkout_allowance_private.aggregate(jsonb_build_array(jsonb_set(r1,'{items,0,unit}','"hour"')));
 if (answer->>'blocked')::boolean is not true or answer#>'{items,0,quantity}'<>'null'::jsonb or answer#>'{items,0,amount_yen}'<>'null'::jsonb or answer#>>'{reasons,0,code}'<>'actual_work_hours_unavailable' then raise exception 'unknown hours must not become zero or day*8';end if;checks:=checks+1;
 begin perform company_checkout_allowance_private.aggregate(jsonb_build_array(jsonb_set(r1,'{items,0,unit}','"month"')));raise exception 'month wrongly accepted';exception when sqlstate '22023' then checks:=checks+1;end;
 begin perform company_checkout_allowance_private.aggregate(jsonb_build_array(jsonb_set(r1,'{items,0,rate_yen}','-1')));raise exception 'negative rate wrongly accepted';exception when sqlstate '22023' then checks:=checks+1;end;
 begin perform company_checkout_allowance_private.aggregate(jsonb_build_array(jsonb_set(r1,'{items,0,rate_yen}','1.5')));raise exception 'fraction rate wrongly accepted';exception when sqlstate '22023' then checks:=checks+1;end;
 begin perform company_checkout_allowance_private.aggregate(jsonb_build_array(r1#-'{items,0,origin}'));raise exception 'missing origin wrongly accepted';exception when sqlstate '22023' then checks:=checks+1;end;
 begin perform company_checkout_allowance_private.aggregate(jsonb_build_array(r1#-'{items,0,section}'));raise exception 'missing section wrongly accepted';exception when sqlstate '22023' then checks:=checks+1;end;
 if has_function_privilege('anon','company_checkout_allowance_private.aggregate(jsonb)','EXECUTE') or has_function_privilege('authenticated','company_checkout_allowance_private.aggregate(jsonb)','EXECUTE') or has_function_privilege('service_role','company_checkout_allowance_private.aggregate(jsonb)','EXECUTE') then raise exception 'public helper exposure';end if;checks:=checks+1;
 raise notice 'RECEIPT_CORE_PASS checks=% production_changed=false actual_auth_tested=false hours_source_connected=false',checks;
end $proof$;
