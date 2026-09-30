-- Aggregate-only Master storage snapshot.
-- Returns counts and bytes only. No object names, paths, file contents,
-- bucket contents, company identities, or user identities are returned.

create or replace function public.get_master_storage_snapshot()
returns jsonb
language sql
stable
security definer
set search_path='public','private','storage','pg_temp'
as $$
  with objects as (
    select
      lower(coalesce(metadata->>'mimetype','')) as mime_type,
      lower(name) as object_name,
      coalesce(nullif(metadata->>'size','')::bigint,0) as size_bytes
    from storage.objects
  )
  select case when public.is_current_user_master_admin() then
    jsonb_build_object(
      'objects_total', (select count(*) from objects),
      'bytes_total', (select coalesce(sum(size_bytes),0) from objects),
      'buckets_with_objects', (
        select count(distinct bucket_id) from storage.objects
      ),
      'images_total', (
        select count(*) from objects
        where mime_type like 'image/%'
           or object_name ~ '\.(png|jpe?g|heic|webp)$'
      ),
      'pdfs_total', (
        select count(*) from objects
        where mime_type='application/pdf'
           or object_name ~ '\.pdf$'
      )
    )
  else null end;
$$;

revoke all on function public.get_master_storage_snapshot()
  from public, anon;
grant execute on function public.get_master_storage_snapshot()
  to authenticated;
