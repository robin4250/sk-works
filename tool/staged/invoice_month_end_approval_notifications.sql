-- STAGED ONLY. Rollout starts OFF; no cron schedule is installed.
-- Generate a formal migration with Supabase CLI after review; do not apply this
-- file to production to test it. No existing notifications are backfilled.
begin;
do $dependencies$
begin
 if not exists(select 1 from pg_proc where oid='private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)'::regprocedure and md5(prosrc)='260ef8dc60ec1917cc0c8dc85ea52872') then raise exception 'dependency drift: enqueue_notification'; end if;
 if not exists(select 1 from pg_proc where oid='private.check_account_access()'::regprocedure and md5(prosrc)='c7f028de1b3703dc4f2b3b57e01b78ef') then raise exception 'dependency drift: check_account_access'; end if;
 if not exists(select 1 from pg_proc where oid='public.account_server_access_allowed(uuid)'::regprocedure and md5(prosrc)='b5a5a5a040399576031c78b31e8b43e9') then raise exception 'dependency drift: account_server_access_allowed'; end if;
end $dependencies$;
create table if not exists private.invoice_month_end_rollout(
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false);
create table if not exists private.invoice_month_end_receipts(
 invoice_id uuid not null references public.invoices(id) on delete cascade,
 recipient_user_id uuid not null,
 approver_registered_at timestamptz not null,
 period_end date not null,
 notification_id uuid not null,
 issued_at timestamptz not null default clock_timestamp(),
 primary key(invoice_id,recipient_user_id,approver_registered_at,period_end));
alter table private.invoice_month_end_rollout enable row level security;
alter table private.invoice_month_end_receipts enable row level security;
revoke all on private.invoice_month_end_rollout,private.invoice_month_end_receipts from public,anon,authenticated;

create or replace function private.invoice_month_end_due(p_end date,p_now timestamptz)
returns boolean language sql immutable set search_path='' as $fn$
 select coalesce((p_now at time zone 'Asia/Tokyo')::date >=
 (date_trunc('month',p_end::timestamp)::date+interval '1 month - 1 day')::date,false)
$fn$;

create or replace function private.invoice_month_end_eligible(p_invoice uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $fn$
 select not exists(select 1 from public.invoices i join private.invoice_month_end_rollout r
 on r.company_id=i.company_id and r.enabled where i.id=p_invoice)
 or exists(select 1 from public.invoices i
 join public.invoice_approvals a on a.invoice_id=i.id and a.company_id=i.company_id and a.approver_user_id=p_user
 join public.invoice_approvers c on c.company_id=i.company_id and c.user_id=p_user
 join public.company_members m on m.company_id=i.company_id and m.user_id=p_user
 join auth.users u on u.id=p_user and u.deleted_at is null
 join private.invoice_month_end_receipts r on r.invoice_id=i.id and r.recipient_user_id=p_user
 and r.approver_registered_at=c.created_at and r.period_end=i.billing_period_end
 where i.id=p_invoice and public.account_server_access_allowed(p_user)
 and private.invoice_month_end_due(i.billing_period_end,current_timestamp))
$fn$;

create or replace function private.dispatch_invoice_month_end_notifications(p_company uuid default null,p_invoice uuid default null)
returns integer language plpgsql security definer set search_path='' as $fn$
declare company record; inv record; approver record; notice uuid; sent integer:=0;
begin
 for company in select c.id from public.companies c
 join private.invoice_month_end_rollout r on r.company_id=c.id and r.enabled
 where p_company is null or c.id=p_company order by c.id
 loop
  perform 1 from public.companies where id=company.id for update;
  for inv in select i.id,i.billing_period_end from public.invoices i
   where i.company_id=company.id and (p_invoice is null or i.id=p_invoice)
   and private.invoice_month_end_due(i.billing_period_end,current_timestamp)
   order by i.id for update
  loop
   perform private.ensure_invoice_approval_rows(inv.id);
   for approver in select a.approver_user_id,c.created_at
    from public.invoice_approvals a
    join public.invoice_approvers c on c.company_id=company.id and c.user_id=a.approver_user_id
    join public.company_members m on m.company_id=company.id and m.user_id=a.approver_user_id
    join auth.users u on u.id=a.approver_user_id and u.deleted_at is null
    where a.invoice_id=inv.id and a.company_id=company.id and a.status='pending'
    and public.account_server_access_allowed(a.approver_user_id)
    and not exists(select 1 from private.invoice_month_end_receipts r
     where r.invoice_id=inv.id and r.recipient_user_id=a.approver_user_id
     and r.approver_registered_at=c.created_at and r.period_end=inv.billing_period_end)
    order by a.position
   loop
    notice:=private.enqueue_notification(company.id,approver.approver_user_id,'approval',
      '請求書の承認依頼','月末の請求書を確認し、承認印を押してください。',
      'invoice_approval',inv.id);
    if notice is null or not exists(select 1 from public.app_notifications n where n.id=notice
      and n.company_id=company.id and n.recipient_user_id=approver.approver_user_id
      and n.action_key='invoice_approval' and n.action_id=inv.id) then
     raise exception 'invoice approval notification was not recorded' using errcode='55000';
    end if;
    insert into private.invoice_month_end_receipts(invoice_id,recipient_user_id,approver_registered_at,period_end,notification_id)
    values(inv.id,approver.approver_user_id,approver.created_at,inv.billing_period_end,notice);
    sent:=sent+1;
   end loop;
  end loop;
 end loop;
 return sent;
end $fn$;

create or replace function private.run_invoice_month_end_notifications()
returns integer language sql security definer set search_path='' as $fn$
 select private.dispatch_invoice_month_end_notifications()
$fn$;
revoke all on function private.invoice_month_end_due(date,timestamptz),
 private.invoice_month_end_eligible(uuid,uuid),
 private.dispatch_invoice_month_end_notifications(uuid,uuid),
 private.run_invoice_month_end_notifications() from public,anon,authenticated,service_role;

do $guard$
declare signature regprocedure:='public.approve_invoice(uuid)'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=signature;
 if original='
-- invoice_month_end_v1

declare uid uuid:=auth.uid(); cid uuid; final boolean;
begin
 if uid is null then raise exception ''authentication required''; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=uid where i.id=p_invoice_id;
 if cid is null then raise exception ''invoice not found''; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.invoices where id=p_invoice_id and company_id=cid for update;
 if not found then raise exception ''invoice not found''; end if;
 perform private.ensure_invoice_approval_rows(p_invoice_id);
 if not exists(select 1 from public.invoice_approvals where invoice_id=p_invoice_id and approver_user_id=uid) then
 raise exception ''invoice approver permission required''; end if;
 if not private.invoice_month_end_eligible(p_invoice_id,uid) then
 raise exception ''invoice approval is available after the month-end notification'' using errcode=''42501''; end if;
 update public.invoice_approvals set status=''approved'',approved_at=clock_timestamp()
 where invoice_id=p_invoice_id and approver_user_id=uid and status=''pending'';
 if found then
 insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,uid,''approved''); end if;
 select count(*)>0 and bool_and(status=''approved'') into final from public.invoice_approvals where invoice_id=p_invoice_id;
 if final then update public.invoices set approval_finalized_at=coalesce(approval_finalized_at,clock_timestamp()) where id=p_invoice_id; end if;
 return coalesce(final,false);
end; ' then return; end if;
 if md5(original)<>'5bc1e283ca727de24f5cf12fac15884c' then raise exception 'definition drift: public.approve_invoice; review before deployment'; end if;
 execute replace(definition,original,'
-- invoice_month_end_v1

declare uid uuid:=auth.uid(); cid uuid; final boolean;
begin
 if uid is null then raise exception ''authentication required''; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=uid where i.id=p_invoice_id;
 if cid is null then raise exception ''invoice not found''; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.invoices where id=p_invoice_id and company_id=cid for update;
 if not found then raise exception ''invoice not found''; end if;
 perform private.ensure_invoice_approval_rows(p_invoice_id);
 if not exists(select 1 from public.invoice_approvals where invoice_id=p_invoice_id and approver_user_id=uid) then
 raise exception ''invoice approver permission required''; end if;
 if not private.invoice_month_end_eligible(p_invoice_id,uid) then
 raise exception ''invoice approval is available after the month-end notification'' using errcode=''42501''; end if;
 update public.invoice_approvals set status=''approved'',approved_at=clock_timestamp()
 where invoice_id=p_invoice_id and approver_user_id=uid and status=''pending'';
 if found then
 insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,uid,''approved''); end if;
 select count(*)>0 and bool_and(status=''approved'') into final from public.invoice_approvals where invoice_id=p_invoice_id;
 if final then update public.invoices set approval_finalized_at=coalesce(approval_finalized_at,clock_timestamp()) where id=p_invoice_id; end if;
 return coalesce(final,false);
end; ');
end $guard$;

do $guard$
declare signature regprocedure:='public.invoice_approval_status_rows(uuid)'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=signature;
 if original='
-- invoice_month_end_v1

declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select i.company_id into v_company_id
  from public.invoices i
  join public.company_members cm
    on cm.company_id=i.company_id and cm.user_id=v_uid
  where i.id=p_invoice_id;

  if v_company_id is null then raise exception ''invoice not found''; end if;

  perform private.ensure_invoice_approval_rows(p_invoice_id);

  return query
  select
    a.approver_user_id,
    coalesce(nullif(up.display_name,''''),''SKOユーザー'')::text,
    a.position::integer,
    a.status,
    a.approved_at,
    (a.approver_user_id=v_uid and a.status=''pending'' and private.invoice_month_end_eligible(p_invoice_id,v_uid))
  from public.invoice_approvals a
  left join public.user_profiles up on up.user_id=a.approver_user_id
  where a.invoice_id=p_invoice_id
  order by a.position;
end;
' then return; end if;
 if md5(original)<>'1e2db926b510083956617e41ff4e9b52' then raise exception 'definition drift: public.invoice_approval_status_rows; review before deployment'; end if;
 execute replace(definition,original,'
-- invoice_month_end_v1

declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select i.company_id into v_company_id
  from public.invoices i
  join public.company_members cm
    on cm.company_id=i.company_id and cm.user_id=v_uid
  where i.id=p_invoice_id;

  if v_company_id is null then raise exception ''invoice not found''; end if;

  perform private.ensure_invoice_approval_rows(p_invoice_id);

  return query
  select
    a.approver_user_id,
    coalesce(nullif(up.display_name,''''),''SKOユーザー'')::text,
    a.position::integer,
    a.status,
    a.approved_at,
    (a.approver_user_id=v_uid and a.status=''pending'' and private.invoice_month_end_eligible(p_invoice_id,v_uid))
  from public.invoice_approvals a
  left join public.user_profiles up on up.user_id=a.approver_user_id
  where a.invoice_id=p_invoice_id
  order by a.position;
end;
');
end $guard$;

do $guard$
declare signature regprocedure:='public.invoice_approval_status_rows_v2(uuid)'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=signature;
 if original='
-- invoice_month_end_v1

declare cid uuid;
begin
 if auth.uid() is null then raise exception ''authentication required''; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id;
 if cid is null then raise exception ''invoice not found''; end if;
 return query select a.approver_user_id,coalesce(nullif(up.display_name,''''),''SKOユーザー'')::text,
 a.position::integer,a.status,a.approved_at,a.approver_user_id=auth.uid() and a.status=''pending'' and private.invoice_month_end_eligible(p_invoice_id,auth.uid()),
 case when a.position=1 and (select count(*) from public.invoice_approvals b where b.invoice_id=a.invoice_id)>1
 then ''confirmation'' else ''approval'' end,
 case when a.status<>''approved'' then null
 when a.display_date_override is not null then a.display_date_override
 when c.invoice_stamp_date_mode=''none'' then null
 when c.invoice_stamp_date_mode=''closing'' then i.billing_period_end
 else (a.approved_at at time zone ''Asia/Tokyo'')::date end,
 c.invoice_stamp_date_mode,a.display_date_override,
 a.approver_user_id=auth.uid() and a.status=''approved'',
 a.status=''approved'' and (a.approver_user_id=auth.uid() or private.has_company_feature(cid,''can_manage_invoices''))
 from public.invoice_approvals a join public.invoices i on i.id=a.invoice_id
 join public.companies c on c.id=i.company_id left join public.user_profiles up on up.user_id=a.approver_user_id
 where a.invoice_id=p_invoice_id order by a.position;
end; ' then return; end if;
 if md5(original)<>'b28a4dff38c401d5374e2930d9028540' then raise exception 'definition drift: public.invoice_approval_status_rows_v2; review before deployment'; end if;
 execute replace(definition,original,'
-- invoice_month_end_v1

declare cid uuid;
begin
 if auth.uid() is null then raise exception ''authentication required''; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id;
 if cid is null then raise exception ''invoice not found''; end if;
 return query select a.approver_user_id,coalesce(nullif(up.display_name,''''),''SKOユーザー'')::text,
 a.position::integer,a.status,a.approved_at,a.approver_user_id=auth.uid() and a.status=''pending'' and private.invoice_month_end_eligible(p_invoice_id,auth.uid()),
 case when a.position=1 and (select count(*) from public.invoice_approvals b where b.invoice_id=a.invoice_id)>1
 then ''confirmation'' else ''approval'' end,
 case when a.status<>''approved'' then null
 when a.display_date_override is not null then a.display_date_override
 when c.invoice_stamp_date_mode=''none'' then null
 when c.invoice_stamp_date_mode=''closing'' then i.billing_period_end
 else (a.approved_at at time zone ''Asia/Tokyo'')::date end,
 c.invoice_stamp_date_mode,a.display_date_override,
 a.approver_user_id=auth.uid() and a.status=''approved'',
 a.status=''approved'' and (a.approver_user_id=auth.uid() or private.has_company_feature(cid,''can_manage_invoices''))
 from public.invoice_approvals a join public.invoices i on i.id=a.invoice_id
 join public.companies c on c.id=i.company_id left join public.user_profiles up on up.user_id=a.approver_user_id
 where a.invoice_id=p_invoice_id order by a.position;
end; ');
end $guard$;

do $guard$
declare signature regprocedure:='private.invoice_approval_rows_trigger()'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=signature;
 if original='
-- invoice_month_end_v1

declare
  r record;
begin
  perform private.ensure_invoice_approval_rows(new.id);
  if exists(select 1 from private.invoice_month_end_rollout cfg where cfg.company_id=new.company_id and cfg.enabled) then
   -- Notification dispatch runs outside invoice write triggers to preserve lock order.
   return null;
  end if;

  if new.billing_period_end <=
      (current_timestamp at time zone ''Asia/Tokyo'')::date then
    for r in
      select a.approver_user_id
      from public.invoice_approvals a
      where a.invoice_id=new.id
        and a.status=''pending''
        and not exists (
          select 1 from public.app_notifications n
          where n.recipient_user_id=a.approver_user_id
            and n.action_key=''invoice_approval''
            and n.action_id=new.id
        )
    loop
      perform private.enqueue_notification(
        new.company_id,
        r.approver_user_id,
        ''approval'',
        ''請求書の確認'',
        ''月末の請求書を確認して承認してください。'',
        ''invoice_approval'',
        new.id
      );
    end loop;
  end if;

  return null;
end;
' then return; end if;
 if md5(original)<>'5b978081e432d0dbf3b8403c293a4646' then raise exception 'definition drift: private.invoice_approval_rows_trigger; review before deployment'; end if;
 execute replace(definition,original,'
-- invoice_month_end_v1

declare
  r record;
begin
  perform private.ensure_invoice_approval_rows(new.id);
  if exists(select 1 from private.invoice_month_end_rollout cfg where cfg.company_id=new.company_id and cfg.enabled) then
   -- Notification dispatch runs outside invoice write triggers to preserve lock order.
   return null;
  end if;

  if new.billing_period_end <=
      (current_timestamp at time zone ''Asia/Tokyo'')::date then
    for r in
      select a.approver_user_id
      from public.invoice_approvals a
      where a.invoice_id=new.id
        and a.status=''pending''
        and not exists (
          select 1 from public.app_notifications n
          where n.recipient_user_id=a.approver_user_id
            and n.action_key=''invoice_approval''
            and n.action_id=new.id
        )
    loop
      perform private.enqueue_notification(
        new.company_id,
        r.approver_user_id,
        ''approval'',
        ''請求書の確認'',
        ''月末の請求書を確認して承認してください。'',
        ''invoice_approval'',
        new.id
      );
    end loop;
  end if;

  return null;
end;
');
end $guard$;

do $guard$
declare signature regprocedure:='public.enqueue_due_invoice_approval_notifications()'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=signature;
 if original='
-- invoice_month_end_v1

declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  r record;
  v_count integer := 0;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_uid
  limit 1;

  if v_company_id is null then return 0; end if;
  perform private.check_account_access();
  if not public.account_server_access_allowed(v_uid) then raise exception ''account access restricted'' using errcode=''42501''; end if;
  if exists(select 1 from private.invoice_month_end_rollout cfg where cfg.company_id=v_company_id and cfg.enabled) then
   return private.dispatch_invoice_month_end_notifications(v_company_id,null);
  end if;

  for r in
    select a.invoice_id,a.approver_user_id
    from public.invoice_approvals a
    join public.invoices i on i.id=a.invoice_id
    where a.company_id=v_company_id
      and a.status=''pending''
      and i.billing_period_end <= (current_timestamp at time zone ''Asia/Tokyo'')::date
      and not exists (
        select 1 from public.app_notifications n
        where n.recipient_user_id=a.approver_user_id
          and n.action_key=''invoice_approval''
          and n.action_id=a.invoice_id
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      r.approver_user_id,
      ''approval'',
      ''請求書の確認'',
      ''月末の請求書を確認して承認してください。'',
      ''invoice_approval'',
      r.invoice_id
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
' then return; end if;
 if md5(original)<>'397e4d08e3fdda359ddf35a4d7e3a9f6' then raise exception 'definition drift: public.enqueue_due_invoice_approval_notifications; review before deployment'; end if;
 execute replace(definition,original,'
-- invoice_month_end_v1

declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  r record;
  v_count integer := 0;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_uid
  limit 1;

  if v_company_id is null then return 0; end if;
  perform private.check_account_access();
  if not public.account_server_access_allowed(v_uid) then raise exception ''account access restricted'' using errcode=''42501''; end if;
  if exists(select 1 from private.invoice_month_end_rollout cfg where cfg.company_id=v_company_id and cfg.enabled) then
   return private.dispatch_invoice_month_end_notifications(v_company_id,null);
  end if;

  for r in
    select a.invoice_id,a.approver_user_id
    from public.invoice_approvals a
    join public.invoices i on i.id=a.invoice_id
    where a.company_id=v_company_id
      and a.status=''pending''
      and i.billing_period_end <= (current_timestamp at time zone ''Asia/Tokyo'')::date
      and not exists (
        select 1 from public.app_notifications n
        where n.recipient_user_id=a.approver_user_id
          and n.action_key=''invoice_approval''
          and n.action_id=a.invoice_id
      )
  loop
    perform private.enqueue_notification(
      v_company_id,
      r.approver_user_id,
      ''approval'',
      ''請求書の確認'',
      ''月末の請求書を確認して承認してください。'',
      ''invoice_approval'',
      r.invoice_id
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
');
end $guard$;
commit;
-- OPERATIONS (not executed here):
-- Verify pg_get_functiondef drift, account guards, RLS/ACL and advisors in staging.
-- Generate the migration using supabase migration new and copy this reviewed SQL.
-- Enable a selected test company only after migration verification, via owner SQL.
-- No public rollout-setting API is introduced.
-- Choose the notification time with the owner before creating a pg_cron job.
-- The eventual owner-only cron command is:
-- select private.run_invoice_month_end_notifications();
-- Do not schedule or invoke it against production as a test.
-- Rollback first disables rollout, then restores only the five captured functions.
-- Retain receipts and notifications for audit. Cancellation alone reuses the receipt.
