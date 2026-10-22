-- READ ONLY: one SELECT returns one JSON object, without any source text or IDs.
-- Run in an externally managed repeatable-read READ ONLY transaction.
-- Whole-table hashes require a quiet comparison window; concurrent app writes
-- may change them and must be investigated, never overwritten.
with source as (
select jsonb_build_object('source_md5',md5(p.prosrc),'attributes',to_jsonb(p)-'prosrc') as source_catalog
from pg_proc p where p.oid=to_regprocedure('private.trade_document_source(text,uuid,text)')
), routines as (
select n.nspname as schema_name,p.proname,pg_get_function_identity_arguments(p.oid) as arguments,
 md5(p.prosrc) as body_md5,to_jsonb(p)-'prosrc' as attributes
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('private','public') and p.proname in
 ('trade_document_source','save_trade_document_attachment','trade_document_attachment_workspace',
 'read_partner_company_profile','save_partner_company_representative')
), table_hashes as (
select 'public.invoices' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.invoices t) hashes
union all
select 'public.payment_certificates' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.payment_certificates t) hashes
union all
select 'public.companies' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.companies t) hashes
union all
select 'public.company_members' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.company_members t) hashes
union all
select 'public.customers' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.customers t) hashes
union all
select 'public.partner_companies' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.partner_companies t) hashes
union all
select 'public.trade_companies' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from public.trade_companies t) hashes
union all
select 'private.trade_document_attachments' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from private.trade_document_attachments t) hashes
union all
select 'private.trade_document_attachment_history' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from private.trade_document_attachment_history t) hashes
union all
select 'private.partner_company_profile_extensions' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from private.partner_company_profile_extensions t) hashes
union all
select 'private.partner_company_profile_audit' as relation,count(*) as rows,
 encode(sha256(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8')),'hex') as all_rows_sha256
 from (select encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex') as row_hash from private.partner_company_profile_audit t) hashes
)
select jsonb_build_object(
 'source_catalog',(select source_catalog from source),
 'routines',(select coalesce(jsonb_agg(to_jsonb(r) order by schema_name,proname,arguments),'[]'::jsonb) from routines r),
 'tables',(select jsonb_agg(to_jsonb(t) order by relation) from table_hashes t)
) as observation;
