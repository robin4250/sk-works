create table if not exists public.communication_albums (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  name text not null,
  description text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.communication_album_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  album_id uuid not null references public.communication_albums(id) on delete cascade,
  storage_path text not null unique,
  caption text,
  original_filename text,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists communication_albums_group_created_idx
  on public.communication_albums(group_id, created_at desc);
create index if not exists communication_album_items_album_created_idx
  on public.communication_album_items(album_id, created_at desc);

alter table public.communication_albums enable row level security;
alter table public.communication_album_items enable row level security;

create policy "company members can manage communication albums"
on public.communication_albums
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_albums.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_albums.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_albums.group_id
      and cg.company_id = communication_albums.company_id
  )
);

create policy "company members can manage communication album items"
on public.communication_album_items
for all
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_album_items.company_id
      and cm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = communication_album_items.company_id
      and cm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.communication_groups cg
    where cg.id = communication_album_items.group_id
      and cg.company_id = communication_album_items.company_id
  )
  and exists (
    select 1 from public.communication_albums ca
    where ca.id = communication_album_items.album_id
      and ca.company_id = communication_album_items.company_id
      and ca.group_id = communication_album_items.group_id
  )
);

insert into storage.buckets (id, name, public)
values ('communication-albums', 'communication-albums', false)
on conflict (id) do update set public = false;

create policy "communication_albums_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.has_storage_company_access(name)
);

create policy "communication_albums_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'communication-albums'
  and private.has_storage_company_access(name)
);

create policy "communication_albums_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.has_storage_company_access(name)
)
with check (
  bucket_id = 'communication-albums'
  and private.has_storage_company_access(name)
);

create policy "communication_albums_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'communication-albums'
  and private.has_storage_company_access(name)
);
