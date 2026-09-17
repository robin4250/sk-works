alter table public.companies
  add column if not exists tax_rate numeric(5,2) not null default 10.00,
  add column if not exists default_unit_price integer not null default 25000,
  add column if not exists default_invoice_detail_mode text not null default 'site_breakdown_on_invoice';

alter table public.companies
  drop constraint if exists companies_default_invoice_detail_mode_check;

alter table public.companies
  add constraint companies_default_invoice_detail_mode_check
  check (default_invoice_detail_mode in (
    'consolidated_only',
    'site_breakdown_on_invoice',
    'site_breakdown_attachment'
  ));
