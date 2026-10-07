-- Display dates never replace immutable audit timestamps. Existing table RLS is retained.
alter table public.companies add column if not exists invoice_stamp_date_mode text
  not null default 'actual' check (invoice_stamp_date_mode in ('actual','closing','none'));
alter table public.invoice_approvals add column if not exists display_date_override date;
-- A trusted server recalculation can have no user actor; preserve its real event time.
alter table public.invoice_approval_audit alter column actor_user_id drop not null;

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

  -- Serialize configuration with approval RPCs before touching invoice rows.
  perform 1 from public.companies where id=v_company_id for update;
  perform 1 from public.invoices where company_id=v_company_id order by id for update;
  if (select array_agg(user_id order by position) from public.invoice_approvers
      where company_id=v_company_id) = p_user_ids then return; end if;
  insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
  select id,company_id,v_uid,'approvers_changed' from public.invoices
  where company_id=v_company_id and status='draft';
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

create or replace function public.invoice_stamp_date_policy()
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid; mode text;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select cm.company_id into cid from public.company_members cm where cm.user_id=auth.uid() limit 1;
 if cid is null then raise exception 'company membership required'; end if;
 select invoice_stamp_date_mode into mode from public.companies where id=cid;
 return jsonb_build_object('mode',mode);
end; $$;
create or replace function public.set_invoice_stamp_date_policy(p_mode text)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select cm.company_id into cid from public.company_members cm where cm.user_id=auth.uid() limit 1;
 if cid is null or not private.has_company_feature(cid,'can_manage_invoices') then
 raise exception 'invoice management permission required'; end if;
 if p_mode is null or p_mode not in ('actual','closing','none') then raise exception 'invalid stamp date mode'; end if;
 update public.companies set invoice_stamp_date_mode=p_mode where id=cid;
end; $$;

create or replace function public.invoice_approval_status_rows_v2(p_invoice_id uuid)
returns table(approver_user_id uuid,approver_name text,"position" integer,status text,
 approved_at timestamptz,can_current_user_approve boolean,stamp_role text,
 display_date date,display_date_mode text,display_date_override date,
 can_current_user_cancel boolean,can_current_user_edit_display_date boolean)
language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id;
 if cid is null then raise exception 'invoice not found'; end if;
 return query select a.approver_user_id,coalesce(nullif(up.display_name,''),'SKOユーザー')::text,
 a.position::integer,a.status,a.approved_at,a.approver_user_id=auth.uid() and a.status='pending',
 case when a.position=1 and (select count(*) from public.invoice_approvals b where b.invoice_id=a.invoice_id)>1
 then 'confirmation' else 'approval' end,
 case when a.status<>'approved' then null
 when a.display_date_override is not null then a.display_date_override
 when c.invoice_stamp_date_mode='none' then null
 when c.invoice_stamp_date_mode='closing' then i.billing_period_end
 else (a.approved_at at time zone 'Asia/Tokyo')::date end,
 c.invoice_stamp_date_mode,a.display_date_override,
 a.approver_user_id=auth.uid() and a.status='approved',
 a.status='approved' and (a.approver_user_id=auth.uid() or private.has_company_feature(cid,'can_manage_invoices'))
 from public.invoice_approvals a join public.invoices i on i.id=a.invoice_id
 join public.companies c on c.id=i.company_id left join public.user_profiles up on up.user_id=a.approver_user_id
 where a.invoice_id=p_invoice_id order by a.position;
end; $$;

create or replace function public.approve_invoice(p_invoice_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); cid uuid; final boolean;
begin
 if uid is null then raise exception 'authentication required'; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=uid where i.id=p_invoice_id;
 if cid is null then raise exception 'invoice not found'; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.invoices where id=p_invoice_id and company_id=cid for update;
 if not found then raise exception 'invoice not found'; end if;
 perform private.ensure_invoice_approval_rows(p_invoice_id);
 if not exists(select 1 from public.invoice_approvals where invoice_id=p_invoice_id and approver_user_id=uid) then
 raise exception 'invoice approver permission required'; end if;
 update public.invoice_approvals set status='approved',approved_at=clock_timestamp()
 where invoice_id=p_invoice_id and approver_user_id=uid and status='pending';
 if found then
 insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,uid,'approved'); end if;
 select count(*)>0 and bool_and(status='approved') into final from public.invoice_approvals where invoice_id=p_invoice_id;
 if final then update public.invoices set approval_finalized_at=coalesce(approval_finalized_at,clock_timestamp()) where id=p_invoice_id; end if;
 return coalesce(final,false);
end; $$;

create or replace function public.cancel_invoice_approval(p_invoice_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id;
 if cid is null then raise exception 'invoice not found'; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.invoices where id=p_invoice_id and company_id=cid for update;
 if not found then raise exception 'invoice not found'; end if;
 if not exists(select 1 from public.invoice_approvals where invoice_id=p_invoice_id and approver_user_id=auth.uid()) then
 raise exception 'invoice approver permission required'; end if;
 update public.invoice_approvals set status='pending',approved_at=null,display_date_override=null
 where invoice_id=p_invoice_id and approver_user_id=auth.uid() and status='approved';
 if found then
 update public.invoices set approval_finalized_at=null where id=p_invoice_id;
 insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,auth.uid(),'cancelled'); end if;
end; $$;

create or replace function public.set_invoice_stamp_display_date(p_invoice_id uuid,p_approver_user_id uuid,p_display_date date)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 select i.company_id into cid from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id;
 if cid is null then raise exception 'invoice not found'; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.invoices where id=p_invoice_id and company_id=cid for update;
 if not found then raise exception 'invoice not found'; end if;
 if p_approver_user_id<>auth.uid() and not private.has_company_feature(cid,'can_manage_invoices') then
 raise exception 'invoice stamp permission required'; end if;
 update public.invoice_approvals set display_date_override=p_display_date
 where invoice_id=p_invoice_id and approver_user_id=p_approver_user_id and status='approved'
 and display_date_override is distinct from p_display_date;
 if found then insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,auth.uid(),'display_date_changed'); end if;
end; $$;

create or replace function public.invoice_approval_history(p_invoice_id uuid)
returns table(actor_name text,action text,created_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 if not exists(select 1 from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id) then raise exception 'invoice not found'; end if;
 return query select case when a.actor_user_id is null then 'システム' else coalesce(nullif(up.display_name,''),'SKOユーザー') end::text,a.action,a.created_at
 from public.invoice_approval_audit a left join public.user_profiles up on up.user_id=a.actor_user_id
 where a.invoice_id=p_invoice_id order by a.created_at desc,a.id;
end; $$;
-- Only material invoice data invalidates approval, never status/audit/display updates.
create or replace function private.invalidate_invoice_approval(p_invoice_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; actor uuid:=auth.uid(); changed boolean;
begin
 select company_id into cid from public.invoices where id=p_invoice_id for update;
 if cid is null then return; end if;
 select exists(select 1 from public.invoice_approvals where invoice_id=p_invoice_id and status='approved') into changed;
 if not changed then return; end if;
 update public.invoice_approvals set status='pending',approved_at=null,display_date_override=null where invoice_id=p_invoice_id;
 update public.invoices set approval_finalized_at=null where id=p_invoice_id;
 -- No actor or approval time is fabricated for server-side recalculation.
 insert into public.invoice_approval_audit(invoice_id,company_id,actor_user_id,action)
 values(p_invoice_id,cid,actor,'content_changed');
end; $$;

create or replace function private.invoice_material_change_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (to_jsonb(new)-array['updated_at','approval_finalized_at','status','finalized_at'])
 is distinct from (to_jsonb(old)-array['updated_at','approval_finalized_at','status','finalized_at']) then
 perform private.invalidate_invoice_approval(new.id); end if;
 return null;
end; $$;
create trigger invoice_material_change_after_update after update on public.invoices
for each row execute function private.invoice_material_change_trigger();

create or replace function private.invoice_detail_material_change_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
declare old_id uuid; new_id uuid;
begin
 if tg_op='UPDATE' and (to_jsonb(new)-array['updated_at','created_at'])=(to_jsonb(old)-array['updated_at','created_at']) then return null; end if;
 if tg_table_name='invoice_site_calculations' then
 if tg_op<>'INSERT' then old_id:=old.invoice_id; end if;
 if tg_op<>'DELETE' then new_id:=new.invoice_id; end if;
 else
 if tg_op<>'INSERT' then select invoice_id into old_id from public.invoice_site_calculations where id=old.invoice_site_calculation_id; end if;
 if tg_op<>'DELETE' then select invoice_id into new_id from public.invoice_site_calculations where id=new.invoice_site_calculation_id; end if;
 end if;
 -- Parent row locks serialize detail changes against approval RPCs.
 if old_id is not null then perform private.invalidate_invoice_approval(old_id); end if;
 if new_id is not null and new_id is distinct from old_id then perform private.invalidate_invoice_approval(new_id); end if;
 return null;
end; $$;
create trigger invoice_calculation_material_change after insert or update or delete on public.invoice_site_calculations
for each row execute function private.invoice_detail_material_change_trigger();
create trigger invoice_line_material_change after insert or update or delete on public.invoice_detail_lines
for each row execute function private.invoice_detail_material_change_trigger();

revoke all on function private.invalidate_invoice_approval(uuid) from public,anon,authenticated;
revoke all on function private.invoice_material_change_trigger() from public,anon,authenticated;
revoke all on function private.invoice_detail_material_change_trigger() from public,anon,authenticated;
revoke all on function public.invoice_stamp_date_policy() from public,anon;
revoke all on function public.set_invoice_stamp_date_policy(text) from public,anon;
revoke all on function public.invoice_approval_status_rows_v2(uuid) from public,anon;
revoke all on function public.cancel_invoice_approval(uuid) from public,anon;
revoke all on function public.set_invoice_stamp_display_date(uuid,uuid,date) from public,anon;
revoke all on function public.invoice_approval_history(uuid) from public,anon;
grant execute on function public.invoice_stamp_date_policy() to authenticated;
grant execute on function public.set_invoice_stamp_date_policy(text) to authenticated;
grant execute on function public.invoice_approval_status_rows_v2(uuid) to authenticated;
grant execute on function public.cancel_invoice_approval(uuid) to authenticated;
grant execute on function public.set_invoice_stamp_display_date(uuid,uuid,date) to authenticated;
grant execute on function public.invoice_approval_history(uuid) to authenticated;
