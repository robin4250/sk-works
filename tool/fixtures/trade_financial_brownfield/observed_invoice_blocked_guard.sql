-- Fixture-only observed-source extract; actual catalog 2026-10-24.
-- Historical Git origin is not established. This is not a migration/installer.
-- md5(prosrc)=f5b4528cdc48a9cf7c97446a8bbe16ac, root reviewed no identifiers/secrets.
CREATE OR REPLACE FUNCTION private.invoice_blocked_finalize_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.calculation_blocked and (new.status<>'draft' or new.finalized_at is not null) then raise exception '勤務区分・現場単価・手当を確認してから請求書を確定してください。'; end if;
 return new;
end;
$function$;
REVOKE ALL ON FUNCTION private.invoice_blocked_finalize_guard() FROM PUBLIC,anon,authenticated,service_role;
