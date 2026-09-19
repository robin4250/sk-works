alter table public.companies
  add column if not exists default_welfare_rate numeric(6,3) not null default 0,
  add column if not exists invoice_template_title text not null default '請求書',
  add column if not exists invoice_footer_note text;

alter table public.companies
  drop constraint if exists companies_default_welfare_rate_check;

alter table public.companies
  add constraint companies_default_welfare_rate_check
  check (default_welfare_rate between 0 and 100);
