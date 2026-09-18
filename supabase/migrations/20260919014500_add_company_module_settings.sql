create table if not exists public.company_module_settings (
  company_id uuid not null references public.companies(id) on delete cascade,
  module_key text not null,
  is_enabled boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (company_id, module_key),
  check (module_key in (
    'qualifications',
    'documents',
    'attendance',
    'sites',
    'chat',
    'notes',
    'albums',
    'invoices',
    'line_bridge'
  ))
);

alter table public.company_module_settings enable row level security;

drop policy if exists "company members can read module settings"
  on public.company_module_settings;
create policy "company members can read module settings"
on public.company_module_settings
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = auth.uid()
  )
);

drop policy if exists "owners and admins can insert module settings"
  on public.company_module_settings;
create policy "owners and admins can insert module settings"
on public.company_module_settings
for insert
to authenticated
with check (
  updated_by = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

drop policy if exists "owners and admins can update module settings"
  on public.company_module_settings;
create policy "owners and admins can update module settings"
on public.company_module_settings
for update
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
)
with check (
  updated_by = auth.uid()
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

-- Absence of a row means enabled. This keeps existing companies compatible
-- and allows disabling a module without deleting any historical module data.
