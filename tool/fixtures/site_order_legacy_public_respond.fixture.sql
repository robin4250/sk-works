-- Verbatim deployed function metadata-only READ ONLY capture 2026-10-30.
CREATE OR REPLACE FUNCTION public.respond_site_share(p_data_item_id uuid, p_accept boolean)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.respond_site_share(p_data_item_id,p_accept) $function$
