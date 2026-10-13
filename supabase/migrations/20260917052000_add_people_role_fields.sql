alter table public.workers
  add column if not exists role text;

alter table public.partner_companies
  add column if not exists trade_role text;
