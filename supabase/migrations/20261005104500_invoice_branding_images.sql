-- Invoice branding images and current reference-logo registration.

alter table public.company_private_billing_settings
  add column if not exists invoice_logo_base64 text,
  add column if not exists invoice_seal_base64 text;

create or replace function public.save_invoice_branding(
  p_logo_base64 text,
  p_seal_base64 text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id,'can_manage_invoices') then
    raise exception 'invoice management permission required';
  end if;

  if length(coalesce(p_logo_base64,'')) > 3000000
     or length(coalesce(p_seal_base64,'')) > 3000000 then
    raise exception 'invoice branding image is too large';
  end if;

  insert into public.company_private_billing_settings(
    company_id, invoice_logo_base64, invoice_seal_base64, updated_by, updated_at
  ) values (
    v_company_id,
    nullif(trim(coalesce(p_logo_base64,'')),''),
    nullif(trim(coalesce(p_seal_base64,'')),''),
    v_user_id,
    now()
  )
  on conflict(company_id) do update
  set invoice_logo_base64=excluded.invoice_logo_base64,
      invoice_seal_base64=excluded.invoice_seal_base64,
      updated_by=v_user_id,
      updated_at=now();
end;
$function$;

revoke all on function public.save_invoice_branding(text,text) from public, anon;
grant execute on function public.save_invoice_branding(text,text) to authenticated;

create or replace function public.invoice_document_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id,'can_view_invoices') then
    raise exception 'invoice view permission required';
  end if;

  select jsonb_build_object(
    'company_name', c.name,
    'company_postal_code', coalesce(c.postal_code,''),
    'company_address', coalesce(c.address,''),
    'company_phone', coalesce(c.phone,''),
    'company_fax', coalesce(c.fax,''),
    'tax_rate', c.tax_rate,
    'welfare_rate', c.default_welfare_rate,
    'template_title', c.invoice_template_title,
    'footer_note', coalesce(c.invoice_footer_note,''),
    'bank_name', coalesce(b.bank_name,''),
    'bank_branch', coalesce(b.bank_branch,''),
    'bank_account_type', coalesce(b.bank_account_type,''),
    'bank_account_number', coalesce(b.bank_account_number,''),
    'bank_account_holder', coalesce(b.bank_account_holder,''),
    'invoice_subject', coalesce(b.invoice_subject,''),
    'invoice_contact_name', coalesce(b.invoice_contact_name,''),
    'payment_due_text', coalesce(b.payment_due_text,''),
    'invoice_logo_base64', coalesce(b.invoice_logo_base64,''),
    'invoice_seal_base64', coalesce(b.invoice_seal_base64,'')
  )
  into v_result
  from public.companies c
  left join public.company_private_billing_settings b on b.company_id=c.id
  where c.id=v_company_id;

  return coalesce(v_result,'{}'::jsonb);
end;
$function$;

revoke all on function public.invoice_document_settings() from public, anon;
grant execute on function public.invoice_document_settings() to authenticated;

-- Register the logo cut from the supplied original invoice and approved seal B
-- for the existing Sumida Construction company without affecting other companies.
update public.company_private_billing_settings b
set invoice_logo_base64=coalesce(nullif(b.invoice_logo_base64,''),'iVBORw0KGgoAAAANSUhEUgAAADwAAAA8CAYAAAA6/NlyAAAAYElEQVR4nO3PAQ0AIRDAsOf9ez5cQDJaBduame8l/+2A0wzXGa4zXGe4znCd4TrDdYbrDNcZrjNcZ7jOcJ3hOsN1husM1xmuM1xnuM5wneE6w3WG6wzXGa4zXGe4znDdBkTIA3Ungm4cAAAAAElFTkSuQmCC'),
    invoice_seal_base64=coalesce(nullif(b.invoice_seal_base64,''),'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'),
    updated_at=now()
from public.companies c
where c.id=b.company_id
  and c.name='すみだ建設株式会社';
