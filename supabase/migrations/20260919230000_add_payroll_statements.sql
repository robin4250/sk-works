create table if not exists public.payroll_statements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  gross_pay integer not null default 0,
  deductions integer not null default 0,
  net_pay integer not null default 0,
  detail jsonb not null default '{}'::jsonb,
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, worker_id, period_start, period_end)
);

create index if not exists payroll_statements_worker_period_idx
  on public.payroll_statements(worker_id, period_end desc);

alter table public.payroll_statements enable row level security;

drop policy if exists "workers and managers can read payroll statements"
  on public.payroll_statements;
create policy "workers and managers can read payroll statements"
on public.payroll_statements
for select
to authenticated
using (
  exists (
    select 1
    from public.workers w
    where w.id = payroll_statements.worker_id
      and w.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.company_members cm
    where cm.company_id = payroll_statements.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

drop policy if exists "owners and admins can manage payroll statements"
  on public.payroll_statements;
create policy "owners and admins can manage payroll statements"
on public.payroll_statements
for all
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = payroll_statements.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = payroll_statements.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);
