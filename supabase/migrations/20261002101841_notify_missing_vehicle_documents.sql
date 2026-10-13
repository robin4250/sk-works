create or replace function public.notify_missing_vehicle_documents(
  p_vehicle_id uuid
)
returns text[]
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_vehicle record;
  v_missing text[] := '{}';
  v_recipient record;
begin
  if v_user is null then
    raise exception 'ログインが必要です';
  end if;

  select cm.company_id, cm.role::text
  into v_company, v_role
  from public.company_members cm
  where cm.user_id = v_user
  limit 1;

  if v_company is null or v_role not in ('owner','admin','manager') then
    raise exception '管理者権限が必要です';
  end if;

  select
    v.id,
    v.company_id,
    v.display_name,
    v.registration_document_path,
    v.compulsory_insurance_path,
    v.voluntary_insurance_path
  into v_vehicle
  from public.vehicles v
  where v.id = p_vehicle_id
    and v.company_id = v_company;

  if v_vehicle.id is null then
    raise exception '車両が見つかりません';
  end if;

  if coalesce(v_vehicle.registration_document_path, '') = '' then
    v_missing := array_append(v_missing, '車検証');
  end if;
  if coalesce(v_vehicle.compulsory_insurance_path, '') = '' then
    v_missing := array_append(v_missing, '自賠責保険');
  end if;
  if coalesce(v_vehicle.voluntary_insurance_path, '') = '' then
    v_missing := array_append(v_missing, '任意保険証書');
  end if;

  if cardinality(v_missing) = 0 then
    update public.app_notifications
    set read_at = coalesce(read_at, now())
    where company_id = v_company
      and action_key = 'vehicle_documents'
      and action_id = p_vehicle_id
      and read_at is null;
    return v_missing;
  end if;

  for v_recipient in
    select cm.user_id
    from public.company_members cm
    where cm.company_id = v_company
      and cm.role::text in ('owner','admin','manager')
  loop
    if not exists (
      select 1
      from public.app_notifications n
      where n.company_id = v_company
        and n.recipient_user_id = v_recipient.user_id
        and n.action_key = 'vehicle_documents'
        and n.action_id = p_vehicle_id
        and n.read_at is null
    ) then
      perform private.enqueue_notification(
        v_company,
        v_recipient.user_id,
        'warning',
        '車両書類を追加してください',
        coalesce(v_vehicle.display_name, '車両') ||
          ' の未登録書類: ' || array_to_string(v_missing, '・'),
        'vehicle_documents',
        p_vehicle_id
      );
    end if;
  end loop;

  return v_missing;
end;
$$;

revoke all on function public.notify_missing_vehicle_documents(uuid)
  from public, anon;
grant execute on function public.notify_missing_vehicle_documents(uuid)
  to authenticated;
