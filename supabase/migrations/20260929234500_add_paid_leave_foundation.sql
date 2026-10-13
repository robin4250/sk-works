-- Paid leave foundation: balances + approval requests.
-- Non-destructive: attendance/payroll integration is handled by follow-up migrations.

create table if not exists public.paid_leave_balances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  granted_days numeric(6,2) not null default 0 check (granted_days >= 0),
  used_days numeric(6,2) not null default 0 check (used_days >= 0),
  expires_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id),
  check (used_days <= granted_days)
);

create table if not exists public.paid_leave_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  leave_date date not null,
  requested_days numeric(4,2) not null default 1 check (requested_days > 0 and requested_days <= 1),
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id, leave_date)
);

create index if not exists paid_leave_requests_company_status_idx
  on public.paid_leave_requests(company_id, status, leave_date);
create index if not exists paid_leave_requests_user_date_idx
  on public.paid_leave_requests(user_id, leave_date desc);

alter table public.paid_leave_balances enable row level security;
alter table public.paid_leave_requests enable row level security;

-- No broad client write policies. Follow-up reviewed RPCs own balance mutation,
-- preventing direct balance edits and requests beyond the remaining allowance.
