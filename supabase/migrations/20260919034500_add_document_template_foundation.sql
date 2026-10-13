-- Shared template library (service-managed) plus editable company copies.
-- No default legal wording is seeded by this migration.

create table if not exists public.document_template_library (
  id uuid primary key default gen_random_uuid(),
  template_key text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.document_template_library_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.document_template_library(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  content_text text not null,
  created_at timestamptz not null default now(),
  unique (template_id, version_number)
);

create table if not exists public.company_document_templates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  source_library_template_id uuid references public.document_template_library(id) on delete set null,
  name text not null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_document_template_versions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  company_template_id uuid not null references public.company_document_templates(id) on delete cascade,
  source_library_version_id uuid references public.document_template_library_versions(id) on delete set null,
  version_number integer not null check (version_number > 0),
  content_text text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (company_template_id, version_number)
);

alter table public.document_requirements
  add column if not exists company_template_id uuid
    references public.company_document_templates(id) on delete set null;

alter table public.worker_document_statuses
  add column if not exists template_version_id uuid
    references public.company_document_template_versions(id) on delete set null;

create index if not exists company_document_templates_company_active_idx
  on public.company_document_templates(company_id, is_active, name);

create index if not exists company_document_template_versions_company_template_idx
  on public.company_document_template_versions(company_id, company_template_id, version_number desc);

alter table public.document_template_library enable row level security;
alter table public.document_template_library_versions enable row level security;
alter table public.company_document_templates enable row level security;
alter table public.company_document_template_versions enable row level security;

drop policy if exists "authenticated users can read active shared document templates"
  on public.document_template_library;
create policy "authenticated users can read active shared document templates"
on public.document_template_library
for select
to authenticated
using (is_active = true);

drop policy if exists "authenticated users can read shared document template versions"
  on public.document_template_library_versions;
create policy "authenticated users can read shared document template versions"
on public.document_template_library_versions
for select
to authenticated
using (
  exists (
    select 1
    from public.document_template_library dt
    where dt.id = document_template_library_versions.template_id
      and dt.is_active = true
  )
);

drop policy if exists "company members can read company document templates"
  on public.company_document_templates;
create policy "company members can read company document templates"
on public.company_document_templates
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "owners and admins can manage company document templates"
  on public.company_document_templates;
create policy "owners and admins can manage company document templates"
on public.company_document_templates
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
);

drop policy if exists "company members can read company document template versions"
  on public.company_document_template_versions;
create policy "company members can read company document template versions"
on public.company_document_template_versions
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "owners and admins can manage company document template versions"
  on public.company_document_template_versions;
create policy "owners and admins can manage company document template versions"
on public.company_document_template_versions
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin')
  )
  and exists (
    select 1 from public.company_document_templates ct
    where ct.id = company_document_template_versions.company_template_id
      and ct.company_id = company_document_template_versions.company_id
  )
);
