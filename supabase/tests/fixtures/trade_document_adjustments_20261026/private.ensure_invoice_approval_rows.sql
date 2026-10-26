CREATE OR REPLACE FUNCTION private.ensure_invoice_approval_rows(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

