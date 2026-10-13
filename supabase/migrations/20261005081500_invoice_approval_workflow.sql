-- Invoice approver configuration, approval state, notifications, and audit trail.

alter table public.invoices
  add column if not exists approval_finalized_at timestamptz;

create table if not exists public.invoice_approvers (
  company_id uuid not null references public.companies(id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (company_id, position),
  unique (company_id, user_id)
);

create table if not exists public.invoice_approvals (
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  approver_user_id uuid not null references auth.users(id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  status text not null default 'pending' check (status in ('pending','approved')),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (invoice_id, approver_user_id),
  unique (invoice_id, position)
);

create table if not exists public.invoice_approval_audit (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  created_at timestamptz not null default now()
);

-- Existing companies begin with their owner as the single invoice approver.
insert into public.invoice_approvers(company_id,position,user_id,created_by)
select cm.company_id,1,cm.user_id,cm.user_id
from public.company_members cm
where cm.role::text='owner'
  and not exists (
    select 1 from public.invoice_approvers ia
    where ia.company_id=cm.company_id
  )
on conflict do nothing;

-- Existing draft invoices receive approval rows immediately.
insert into public.invoice_approvals(
  invoice_id,company_id,approver_user_id,position,status
)
select i.id,i.company_id,ia.user_id,ia.position,'pending'
from public.invoices i
join public.invoice_approvers ia on ia.company_id=i.company_id
where i.status='draft'
on conflict(invoice_id,approver_user_id) do nothing;

alter table public.invoice_approvers enable row level security;
alter table public.invoice_approvals enable row level security;
alter table public.invoice_approval_audit enable row level security;

revoke all on public.invoice_approvers from anon, authenticated;
revoke all on public.invoice_approvals from anon, authenticated;
revoke all on public.invoice_approval_audit from anon, authenticated;

create or replace function public.invoice_approver_rows()
returns table(
  user_id uuid,
  display_name text,
  role text,
  selected_position integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_uid
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id,'can_manage_invoices') then
    raise exception 'invoice management permission required';
  end if;

  return query
  select
    cm.user_id,
    coalesce(nullif(up.display_name,''),'SKOユーザー')::text,
    cm.role::text,
    ia.position::integer
  from public.company_members cm
  left join public.user_profiles up on up.user_id=cm.user_id
  left join public.invoice_approvers ia
    on ia.company_id=cm.company_id and ia.user_id=cm.user_id
  where cm.company_id=v_company_id
  order by coalesce(ia.position,99), coalesce(nullif(up.display_name,''),'SKOユーザー');
end;
$$;

create or replace function public.set_invoice_approvers(p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_count integer;
  v_item uuid;
  v_pos integer := 0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_uid
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id,'can_manage_invoices') then
    raise exception 'invoice management permission required';
  end if;

  v_count := coalesce(array_length(p_user_ids,1),0);
  if v_count < 1 or v_count > 3 then
    raise exception 'invoice approvers must contain 1 to 3 users';
  end if;

  if (select count(distinct x) from unnest(p_user_ids) x) <> v_count then
    raise exception 'invoice approvers must be unique';
  end if;

  foreach v_item in array p_user_ids loop
    if not exists (
      select 1 from public.company_members cm
      where cm.company_id=v_company_id and cm.user_id=v_item
    ) then
      raise exception 'approver must be a registered company user';
    end if;
  end loop;

  delete from public.invoice_approvers where company_id=v_company_id;

  foreach v_item in array p_user_ids loop
    v_pos := v_pos + 1;
    insert into public.invoice_approvers(company_id,position,user_id,created_by)
    values(v_company_id,v_pos,v_item,v_uid);
  end loop;

  delete from public.invoice_approvals a
  using public.invoices i
  where a.invoice_id=i.id
    and i.company_id=v_company_id
    and i.status='draft';

  update public.invoices
  set approval_finalized_at=null
  where company_id=v_company_id and status='draft';

  insert into public.invoice_approvals(
    invoice_id,company_id,approver_user_id,position,status
  )
  select i.id,i.company_id,ia.user_id,ia.position,'pending'
  from public.invoices i
  join public.invoice_approvers ia on ia.company_id=i.company_id
  where i.company_id=v_company_id and i.status='draft'
  on conflict(invoice_id,approver_user_id) do nothing;
end;
$$;

create or replace function private.ensure_invoice_approval_rows(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.invoice_approvals(
    invoice_id,company_id,approver_user_id,position,status
  )
  select i.id,i.company_id,ia.user_id,ia.position,'pending'
  from public.invoices i
  join public.invoice_approvers ia on ia.company_id=i.company_id
  where i.id=p_invoice_id
  on conflict(invoice_id,approver_user_id) do nothing;
end;
$$;

create or replace function private.invoice_approval_rows_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  perform private.ensure_invoice_approval_rows(new.id);

  if new.billing_period_end <=
      (current_timestamp at time zone 'Asia/Tokyo')::date then
    for r in
      select a.approver_user_id
      from public.invoice_approvals a
      where a.invoice_id=new.id
        and a.status='pending'
        and not exists (
          select 1 from public.app_notifications n
          where n.recipient_user_id=a.approver_user_id
            and n.action_key='invoice_approval'
            and n.action_id=new.id
        )
    loop
      perform private.enqueue_notification(
        new.company_id,
        r.approver_user_id,
        'approval',
        '請求書の確認',
        '月末の請求書を確認して承認してください。',
        'invoice_approval',
        new.id
      );
    end loop;
  end if;

  return null;
end;
$$;

drop trigger if exists invoice_approval_rows_after_write on public.invoices;
create trigger invoice_approval_rows_after_write
after insert or update on public.invoices
for each row execute function private.invoice_approval_rows_trigger();

create or replace function public.invoice_approval_status_rows(p_invoice_id uuid)
returns table(
  approver_user_id uuid,
  approver_name text,
  "position" integer,
  status text,
  approved_at timestamptz,
  can_current_user_approve boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select i.company_id into v_company_id
  from public.invoices i
  join public.company_members cm
    on cm.company_id=i.company_id and cm.user_id=v_uid
  where i.id=p_invoice_id;

  if v_company_id is null then raise exception 'invoice not found'; end if;

  perform private.ensure_invoice_approval_rows(p_invoice_id);

  return query
  select
    a.approver_user_id,
    coalesce(nullif(up.display_name,''),'SKOユーザー')::text,
    a.position::integer,
    a.status,
    a.approved_at,
    (a.approver_user_id=v_uid and a.status='pending')
  from public.invoice_approvals a
  left join public.user_profiles up on up.user_id=a.approver_user_id
  where a.invoice_id=p_invoice_id
  order by a.position;
end;
$$;

create or replace function public.approve_invoice(p_invoice_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_final boolean;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select i.company_id into v_company_id
  from public.invoices i
  where i.id=p_invoice_id
  for update;

  if v_company_id is null then raise exception 'invoice not found'; end if;

  perform private.ensure_invoice_approval_rows(p_invoice_id);

  if not exists (
    select 1 from public.invoice_approvals a
    where a.invoice_id=p_invoice_id
      and a.approver_user_id=v_uid
  ) then
    raise exception 'invoice approver permission required';
  end if;

  update public.invoice_approvals
  set status='approved', approved_at=coalesce(approved_at,now())
  where invoice_id=p_invoice_id
    and approver_user_id=v_uid
    and status='pending';

  insert into public.invoice_approval_audit(
    invoice_id,company_id,actor_user_id,action
  )
  values(p_invoice_id,v_company_id,v_uid,'approved');

  select not exists(
    select 1 from public.invoice_approvals
    where invoice_id=p_invoice_id and status<>'approved'
  ) into v_final;

  if v_final then
    update public.invoices
    set approval_finalized_at=coalesce(approval_finalized_at,now())
    where id=p_invoice_id;
  end if;

  return v_final;
end;
$$;

create or replace function public.enqueue_due_invoice_approval_notifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  r record;
  v_count integer := 0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_uid
  limit 1;

  if v_company_id is null then return 0; end if;

  for r in
    select a.invoice_id,a.approver_user_id
    from public.invoice_approvals a
    join public.invoices i on i.id=a.invoice_id
    where a.company_id=v_company_id
      and a.status='pending'
      and i.billing_period_end <= (current_timestamp at time zone 'Asia/Tokyo')::date
      and not exists (
        select 1 from public.app_notifications n
        where n.recipient_user_id=a.approver_user_id
          and n.action_key='invoice_approval'
          and n.action_id=a.invoice_id
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      r.approver_user_id,
      'approval',
      '請求書の確認',
      '月末の請求書を確認して承認してください。',
      'invoice_approval',
      r.invoice_id
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.invoice_approver_rows() from public, anon;
revoke all on function public.set_invoice_approvers(uuid[]) from public, anon;
revoke all on function public.invoice_approval_status_rows(uuid) from public, anon;
revoke all on function public.approve_invoice(uuid) from public, anon;
revoke all on function public.enqueue_due_invoice_approval_notifications() from public, anon;

grant execute on function public.invoice_approver_rows() to authenticated;
grant execute on function public.set_invoice_approvers(uuid[]) to authenticated;
grant execute on function public.invoice_approval_status_rows(uuid) to authenticated;
grant execute on function public.approve_invoice(uuid) to authenticated;
grant execute on function public.enqueue_due_invoice_approval_notifications() to authenticated;
