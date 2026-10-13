revoke select on table public.companies from authenticated;

grant select (
  id,
  name,
  postal_code,
  address,
  phone,
  invoice_registration_number,
  created_at,
  updated_at,
  tax_rate,
  default_unit_price,
  default_invoice_detail_mode,
  fax,
  email,
  default_welfare_rate,
  invoice_template_title,
  invoice_footer_note
) on table public.companies to authenticated;
