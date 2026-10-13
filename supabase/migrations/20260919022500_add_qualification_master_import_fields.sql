alter table public.qualification_master
  add column if not exists is_active boolean not null default true,
  add column if not exists source_name text,
  add column if not exists source_reference text,
  add column if not exists source_updated_at date,
  add column if not exists external_source_id text,
  add column if not exists is_company_custom boolean not null default true;

create unique index if not exists qualification_master_source_external_uidx
  on public.qualification_master(company_id, source_name, external_source_id)
  where source_name is not null and external_source_id is not null;

create table if not exists public.qualification_master_aliases (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  qualification_master_id uuid not null references public.qualification_master(id) on delete cascade,
  alias_name text not null,
  created_at timestamptz not null default now(),
  unique (company_id, qualification_master_id, alias_name)
);

create index if not exists qualification_master_aliases_company_alias_idx
  on public.qualification_master_aliases(company_id, alias_name);

alter table public.qualification_master_aliases enable row level security;

drop policy if exists "company members can manage qualification aliases"
  on public.qualification_master_aliases;
create policy "company members can manage qualification aliases"
on public.qualification_master_aliases
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.qualification_master qm
    where qm.id = qualification_master_aliases.qualification_master_id
      and qm.company_id = qualification_master_aliases.company_id
  )
);
