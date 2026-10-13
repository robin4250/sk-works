create or replace function public.current_user_required_document_attention()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_worker_id uuid;
  v_missing_names text[];
  v_missing_count integer;
begin
  if v_user_id is null then
    return jsonb_build_object(
      'missing_count', 0,
      'missing_names', '[]'::jsonb,
      'needs_license', false,
      'needs_qualification', false
    );
  end if;

  select w.company_id, w.id
  into v_company_id, v_worker_id
  from public.workers w
  where w.user_id = v_user_id
    and w.status = 'active'
  limit 1;

  if v_company_id is null or v_worker_id is null then
    return jsonb_build_object(
      'missing_count', 0,
      'missing_names', '[]'::jsonb,
      'needs_license', false,
      'needs_qualification', false
    );
  end if;

  select
    count(*)::integer,
    coalesce(array_agg(dr.name order by dr.sort_order, dr.name), array[]::text[])
  into v_missing_count, v_missing_names
  from public.document_requirements dr
  left join public.worker_document_statuses wds
    on wds.requirement_id = dr.id
   and wds.worker_id = v_worker_id
   and wds.company_id = v_company_id
  where dr.company_id = v_company_id
    and dr.is_active
    and dr.is_required
    and (
      wds.id is null
      or wds.status in ('not_submitted','missing','expired')
    );

  return jsonb_build_object(
    'missing_count', coalesce(v_missing_count, 0),
    'missing_names', to_jsonb(coalesce(v_missing_names, array[]::text[])),
    'needs_license', exists (
      select 1
      from unnest(coalesce(v_missing_names, array[]::text[])) n
      where n like '%免許%'
    ),
    'needs_qualification', exists (
      select 1
      from unnest(coalesce(v_missing_names, array[]::text[])) n
      where n like '%資格%'
    )
  );
end;
$$;

revoke execute on function public.current_user_required_document_attention()
  from public, anon;
grant execute on function public.current_user_required_document_attention()
  to authenticated;
