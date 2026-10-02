create or replace function private.notify_management_of_attendance_location()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_worker_name text;
  v_site_name text;
  v_event_label text;
  v_recipient record;
begin
  if new.latitude is null or new.longitude is null then
    return new;
  end if;

  select w.name into v_worker_name
  from public.workers w
  where w.id = new.worker_id;

  select s.name into v_site_name
  from public.sites s
  where s.id = new.site_id;

  v_event_label := case
    when new.event_type = 'clock_out' then '退勤'
    else '出勤'
  end;

  for v_recipient in
    select cm.user_id
    from public.company_members cm
    where cm.company_id = new.company_id
      and cm.role::text in ('owner','admin','manager')
  loop
    perform private.enqueue_notification(
      new.company_id,
      v_recipient.user_id,
      'attendance',
      '最新の打刻位置',
      coalesce(v_worker_name, '社員') || 'さんが' || v_event_label ||
        'しました。' ||
        case
          when coalesce(v_site_name, '') <> ''
            then ' 現場: ' || v_site_name || '。'
          else '。'
        end ||
        ' 現場マップで最新の打刻位置を確認できます。',
      'site_map',
      new.id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists notify_management_of_attendance_location
  on public.attendance_verifications;

create trigger notify_management_of_attendance_location
after insert on public.attendance_verifications
for each row
execute function private.notify_management_of_attendance_location();

revoke all on function private.notify_management_of_attendance_location()
  from public, anon, authenticated;
