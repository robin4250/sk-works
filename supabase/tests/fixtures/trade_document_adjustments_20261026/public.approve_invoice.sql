CREATE OR REPLACE FUNCTION public.approve_invoice(p_invoice_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$;

