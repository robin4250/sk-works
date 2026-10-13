create or replace function private.notify_site_information_request_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_notifications(
    company_id,
    recipient_user_id,
    kind,
    title,
    body,
    action_key,
    action_id
  )
  select distinct
    new.company_id,
    x.user_id,
    'approval',
    '現場データの変更申請',
    '現場情報の変更・終了申請があります。内容を確認して承認または差し戻してください。',
    'site_information_request',
    new.id
  from (
    select cm.user_id
    from public.company_members cm
    where cm.company_id = new.company_id
      and cm.role::text in ('owner','admin','manager')
    union
    select a.user_id
    from public.company_approval_assignees a
    where a.company_id = new.company_id
  ) x
  where x.user_id <> new.requested_by;

  return new;
end
$$;

drop trigger if exists site_information_request_notify_insert
  on private.site_information_requests;
create trigger site_information_request_notify_insert
after insert on private.site_information_requests
for each row
when (new.status = 'pending')
execute function private.notify_site_information_request_insert();

create or replace function private.notify_site_information_request_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending'
     and new.status in ('approved','rejected')
     and new.status is distinct from old.status then
    insert into public.app_notifications(
      company_id,
      recipient_user_id,
      kind,
      title,
      body,
      action_key,
      action_id
    )
    values(
      new.company_id,
      new.requested_by,
      case when new.status='approved' then 'approval' else 'warning' end,
      case
        when new.status='approved' then '現場データの変更が承認されました'
        else '現場データの変更が差し戻されました'
      end,
      case
        when new.status='approved' then '申請した現場情報の変更が承認され、現場データへ反映されました。'
        else '申請した現場情報の変更が差し戻されました。内容を確認してください。'
      end,
      'site_information_request_result',
      new.id
    );
  end if;
  return new;
end
$$;

drop trigger if exists site_information_request_notify_result
  on private.site_information_requests;
create trigger site_information_request_notify_result
after update of status on private.site_information_requests
for each row
execute function private.notify_site_information_request_result();
