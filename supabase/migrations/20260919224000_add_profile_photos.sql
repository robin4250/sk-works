alter table public.user_profiles
  add column if not exists avatar_storage_path text;

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do update set public = false;

drop policy if exists "profile_photos_read" on storage.objects;
create policy "profile_photos_read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'profile-photos'
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or exists (
      select 1
      from public.company_members me
      join public.company_members other
        on other.company_id = me.company_id
      where me.user_id = auth.uid()
        and other.user_id::text = split_part(name, '/', 1)
    )
  )
);

drop policy if exists "profile_photos_insert" on storage.objects;
create policy "profile_photos_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "profile_photos_update" on storage.objects;
create policy "profile_photos_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
)
with check (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "profile_photos_delete" on storage.objects;
create policy "profile_photos_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-photos'
  and split_part(name, '/', 1) = auth.uid()::text
);

create or replace function public.company_member_profiles()
returns table(
  user_id uuid,
  display_name text,
  avatar_storage_path text,
  role text
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with my_company as (
    select cm.company_id
    from public.company_members cm
    where cm.user_id = auth.uid()
    limit 1
  )
  select
    cm.user_id,
    coalesce(up.display_name, 'SKOユーザー') as display_name,
    up.avatar_storage_path,
    cm.role::text
  from public.company_members cm
  join my_company mc on mc.company_id = cm.company_id
  left join public.user_profiles up on up.user_id = cm.user_id
  order by display_name;
$$;

revoke execute on function public.company_member_profiles() from public, anon;
grant execute on function public.company_member_profiles() to authenticated;
