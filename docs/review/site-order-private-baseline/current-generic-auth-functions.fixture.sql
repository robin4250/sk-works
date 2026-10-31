-- Catalog function definitions only; no business rows. Selected sources contain no company identifiers.
CREATE OR REPLACE FUNCTION auth.jwt()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$function$
;
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$
;
CREATE OR REPLACE FUNCTION private.account_deletion_barrier_key(p_user uuid)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
 select pg_catalog.hashtextextended('sko:account-deletion:data-api:'||p_user::text,0)
$function$
;
