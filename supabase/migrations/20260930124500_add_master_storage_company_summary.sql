-- Aggregate-only company storage distribution for Master analytics.
-- Company identities, object names, paths and file contents are never returned.

create or replace function public.get_master_storage_company_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path='public','private','storage','pg_temp'
as $$
declare
  v_result jsonb;
begin
  if not public.is_current_user_master_admin() then
    return null;
  end if;

  with object_rows as (
    select
      case
        when (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then ((storage.foldername(name))[1])::uuid
        else null
      end as company_id,
      lower(coalesce(metadata->>'mimetype','')) as mime_type,
      lower(name) as object_name,
      coalesce(nullif(metadata->>'size','')::bigint,0) as size_bytes
    from storage.objects
  ),
  company_storage as (
    select
      c.id as company_id,
      count(o.company_id)::bigint as object_count,
      coalesce(sum(o.size_bytes),0)::bigint as bytes_total,
      count(o.company_id) filter (
        where o.mime_type like 'image/%'
           or o.object_name ~ '\.(png|jpe?g|heic|webp)$'
      )::bigint as images_total,
      count(o.company_id) filter (
        where o.mime_type='application/pdf'
           or o.object_name ~ '\.pdf$'
      )::bigint as pdfs_total,
      count(o.company_id) filter (
        where not (
          o.mime_type like 'image/%'
          or o.object_name ~ '\.(png|jpe?g|heic|webp)$'
          or o.mime_type='application/pdf'
          or o.object_name ~ '\.pdf$'
        )
      )::bigint as attachments_total
    from public.companies c
    left join object_rows o on o.company_id=c.id
    group by c.id
  )
  select jsonb_build_object(
    'companies_total', count(*),
    'companies_with_files', count(*) filter (where object_count > 0),
    'companies_without_files', count(*) filter (where object_count = 0),
    'objects_total', coalesce(sum(object_count),0),
    'bytes_total', coalesce(sum(bytes_total),0),
    'average_bytes_per_company', coalesce(round(avg(bytes_total)::numeric,2),0),
    'max_bytes_per_company', coalesce(max(bytes_total),0),
    'min_bytes_per_company', coalesce(min(bytes_total),0),
    'average_images_per_company', coalesce(round(avg(images_total)::numeric,2),0),
    'max_images_per_company', coalesce(max(images_total),0),
    'average_pdfs_per_company', coalesce(round(avg(pdfs_total)::numeric,2),0),
    'max_pdfs_per_company', coalesce(max(pdfs_total),0),
    'average_attachments_per_company', coalesce(round(avg(attachments_total)::numeric,2),0),
    'max_attachments_per_company', coalesce(max(attachments_total),0)
  )
  into v_result
  from company_storage;

  return v_result;
end;
$$;

revoke all on function public.get_master_storage_company_summary()
  from public, anon;
grant execute on function public.get_master_storage_company_summary()
  to authenticated;
