create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'info',
  title text not null,
  body text,
  action_key text,
  action_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists app_notifications_recipient_created_idx
  on public.app_notifications(recipient_user_id, created_at desc);

create index if not exists app_notifications_recipient_unread_idx
  on public.app_notifications(recipient_user_id, read_at)
  where read_at is null;

alter table public.app_notifications enable row level security;

drop policy if exists "users can read own notifications" on public.app_notifications;
create policy "users can read own notifications"
on public.app_notifications
for select
to authenticated
using (recipient_user_id = auth.uid());

drop policy if exists "users can mark own notifications read" on public.app_notifications;
create policy "users can mark own notifications read"
on public.app_notifications
for update
to authenticated
using (recipient_user_id = auth.uid())
with check (recipient_user_id = auth.uid());

create or replace function public.mark_all_notifications_read()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.app_notifications
  set read_at = coalesce(read_at, now())
  where recipient_user_id = auth.uid()
    and read_at is null;
$$;

revoke execute on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated;

create or replace function private.enqueue_notification(
  p_company_id uuid,
  p_recipient_user_id uuid,
  p_kind text,
  p_title text,
  p_body text default null,
  p_action_key text default null,
  p_action_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_id uuid;
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
  values(
    p_company_id,
    p_recipient_user_id,
    coalesce(nullif(trim(p_kind), ''), 'info'),
    p_title,
    p_body,
    p_action_key,
    p_action_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function private.enqueue_notification(
  uuid, uuid, text, text, text, text, uuid
) from public, anon, authenticated;
