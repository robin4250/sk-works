-- Exact captured settings notification trigger ; atomic function is applied from the adopted main source migration; fixture-only dependency.
CREATE OR REPLACE FUNCTION private.refresh_generation_setting_issues_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid;
begin
  cid:=case when tg_op='DELETE' then old.company_id else new.company_id end;
  perform private.refresh_generation_setting_issues(cid);
  if tg_op='UPDATE' and old.company_id is distinct from new.company_id then
    perform private.refresh_generation_setting_issues(old.company_id);
  end if;
  return null;
end;
$function$
;
CREATE TRIGGER payroll_settings_refresh_generation_setting_issues AFTER INSERT OR DELETE OR UPDATE ON worker_payroll_settings FOR EACH ROW EXECUTE FUNCTION private.refresh_generation_setting_issues_trigger();
