-- Aggregate-only Master storage snapshot.
-- Returns counts and bytes only. No object names, paths, file contents,
-- bucket contents, company identities, or user identities are returned.

create or replace function public.get_master_storage_snapshot()
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

  with objects as (
    select
      lower(coalesce(metadata->>'mimetype','')) as mime_type,
      lower(name) as object_name,
      coalesce(nullif(metadata->>'size','')::bigint,0) as size_bytes,
      bucket_id
    from storage.objects
  )
  select jsonb_build_object(
    'objects_total', count(*),
    'bytes_total', coalesce(sum(size_bytes),0),
    'buckets_with_objects', count(distinct bucket_id),
    'images_total', count(*) filter (
      where mime_type like 'image/%'
         or object_name ~ '\.(png|jpe?g|heic|webp)$'
    ),
    'pdfs_total', count(*) filter (
      where mime_type='application/pdf'
         or object_name ~ '\.pdf$'
    )
  )
  into v_result
  from objects;

  return v_result;
end;
$$;

revoke all on function public.get_master_storage_snapshot()
  from public, anon;
grant execute on function public.get_master_storage_snapshot()
  to authenticated;
