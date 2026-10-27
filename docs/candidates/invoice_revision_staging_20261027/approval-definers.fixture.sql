-- Exact catalog definitions, captured before this test. No business records.
CREATE OR REPLACE FUNCTION public.invoice_approval_history(p_invoice_id uuid)
 RETURNS TABLE(actor_name text, action text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 if not exists(select 1 from public.invoices i join public.company_members cm
 on cm.company_id=i.company_id and cm.user_id=auth.uid() where i.id=p_invoice_id) then raise exception 'invoice not found'; end if;
 return query select case when a.actor_user_id is null then 'システム' else coalesce(nullif(up.display_name,''),'SKOユーザー') end::text,a.action,a.created_at
 from public.invoice_approval_audit a left join public.user_profiles up on up.user_id=a.actor_user_id
 where a.invoice_id=p_invoice_id order by a.created_at desc,a.id;
end; $function$;

CREATE OR REPLACE FUNCTION public.invoice_approval_status_rows(p_invoice_id uuid)
 RETURNS TABLE(approver_user_id uuid, approver_name text, "position" integer, status text, approved_at timestamp with time zone, can_current_user_approve boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.invoice_approval_status_rows_v2(p_invoice_id uuid)
 RETURNS TABLE(approver_user_id uuid, approver_name text, "position" integer, status text, approved_at timestamp with time zone, can_current_user_approve boolean, stamp_role text, display_date date, display_date_mode text, display_date_override date, can_current_user_cancel boolean, can_current_user_edit_display_date boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$;
