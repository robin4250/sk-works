alter table public.sites
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

create table if not exists public.attendance_verification_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  mode text not null default 'manual' check (mode in ('manual', 'location', 'location_photo')),
  proximity_radius_m integer not null default 300 check (proximity_radius_m between 25 and 5000),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.attendance_verifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  event_type text not null check (event_type in ('clock_in', 'clock_out')),
  verification_mode text not null check (verification_mode in ('manual', 'location', 'location_photo')),
  confirmed_at timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  distance_to_site_m double precision,
  proximity_status text not null default 'not_checked' check (proximity_status in ('not_checked', 'near_site', 'outside_radius', 'site_location_missing')),
  photo_storage_path text,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (
    verification_mode = 'manual'
    or (latitude is not null and longitude is not null)
  ),
  check (
    verification_mode <> 'location_photo'
    or photo_storage_path is not null
  )
);

create index if not exists attendance_verifications_company_confirmed_idx
  on public.attendance_verifications(company_id, confirmed_at desc);
create index if not exists attendance_verifications_worker_confirmed_idx
  on public.attendance_verifications(worker_id, confirmed_at desc);
create index if not exists attendance_verifications_site_confirmed_idx
  on public.attendance_verifications(site_id, confirmed_at desc);

alter table public.attendance_verification_settings enable row level security;
alter table public.attendance_verifications enable row level security;

create policy "company members can manage attendance verification settings"
on public.attendance_verification_settings
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = attendance_verification_settings.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = attendance_verification_settings.company_id
      and cm.user_id = auth.uid()
  )
);

create policy "company members can manage attendance verifications"
on public.attendance_verifications
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = attendance_verifications.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = attendance_verifications.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.workers w
    where w.id = attendance_verifications.worker_id
      and w.company_id = attendance_verifications.company_id
  )
  and exists (
    select 1 from public.sites s
    where s.id = attendance_verifications.site_id
      and s.company_id = attendance_verifications.company_id
  )
);

insert into storage.buckets (id, name, public)
values ('attendance-evidence', 'attendance-evidence', false)
on conflict (id) do update set public = false;

create policy "attendance_evidence_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and private.has_storage_company_access(name)
);

create policy "attendance_evidence_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'attendance-evidence'
  and private.has_storage_company_access(name)
);

create policy "attendance_evidence_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and private.has_storage_company_access(name)
)
with check (
  bucket_id = 'attendance-evidence'
  and private.has_storage_company_access(name)
);

create policy "attendance_evidence_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'attendance-evidence'
  and private.has_storage_company_access(name)
);