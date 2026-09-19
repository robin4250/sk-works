create table if not exists public.site_financial_settings (
  site_id uuid primary key references public.sites(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_daily_rate_yen integer not null default 0,
  overtime_hour_rate_yen integer not null default 0,
  early_hour_rate_yen integer not null default 0,
  night_hour_rate_yen integer not null default 0,
  billing_unit_price_yen integer not null default 0,
  welfare_rate numeric(6,3) not null default 0,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists site_financial_settings_company_idx
  on public.site_financial_settings(company_id);

alter table public.site_financial_settings enable row level security;

drop policy if exists "owners and admins can read site financial settings"
  on public.site_financial_settings;
create policy "owners and admins can read site financial settings"
on public.site_financial_settings
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_financial_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

drop policy if exists "owners and admins can manage site financial settings"
  on public.site_financial_settings;
create policy "owners and admins can manage site financial settings"
on public.site_financial_settings
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_financial_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = site_financial_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);
