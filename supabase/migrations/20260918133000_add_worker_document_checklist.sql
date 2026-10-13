create table if not exists public.document_requirements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  scope text not null default 'internal'
    check (scope in ('internal', 'upstream')),
  is_required boolean not null default true,
  expiry_required boolean not null default false,
  renewal_reminder_days integer not null default 30
    check (renewal_reminder_days >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, scope, name)
);

create table if not exists public.worker_document_statuses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  requirement_id uuid not null references public.document_requirements(id) on delete cascade,
  status text not null default 'not_submitted'
    check (status in ('not_submitted', 'submitted', 'verified', 'missing', 'expired')),
  expires_at date,
  original_verified boolean not null default false,
  attachment_path text,
  notes text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (worker_id, requirement_id)
);

create index if not exists document_requirements_company_scope_idx
  on public.document_requirements(company_id, scope, is_active, sort_order);
create index if not exists worker_document_statuses_company_worker_idx
  on public.worker_document_statuses(company_id, worker_id);

alter table public.document_requirements enable row level security;
alter table public.worker_document_statuses enable row level security;

create policy "company members can manage document requirements"
on public.document_requirements
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "company members can manage worker document statuses"
on public.worker_document_statuses
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_statuses.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
  )
  and exists (
    select 1 from public.document_requirements dr
    where dr.id = worker_document_statuses.requirement_id
      and dr.company_id = worker_document_statuses.company_id
  )
);
