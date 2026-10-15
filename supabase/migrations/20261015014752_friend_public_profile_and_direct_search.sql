-- Only approved friends may read these public identity fields.
create or replace function private.can_read_friend_identity(p_other uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed() is true
 and p_other<>auth.uid()
 -- Same persisted restriction used by account_access_allowed(), for the peer.
 and not exists(select 1 from private.account_deletion_access_restrictions r
   where r.user_id=p_other)
 and exists(select 1 from auth.users u where u.id=auth.uid() and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and exists(select 1 from auth.users u where u.id=p_other and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and exists(select 1 from private.sko_friends f where
   (f.user_a=auth.uid() and f.user_b=p_other) or
   (f.user_b=auth.uid() and f.user_a=p_other))
$$;
revoke all on function private.can_read_friend_identity(uuid) from public, anon;
grant execute on function private.can_read_friend_identity(uuid) to authenticated;

create or replace function private.sko_friend_public_profiles()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'user_id',p.user_id,'display_name',p.display_name,
   'avatar_storage_path',case when split_part(p.avatar_storage_path,'/',1)=p.user_id::text then p.avatar_storage_path end,
   'company_name',(select string_agg(distinct c.name,' / ' order by c.name)
     from public.company_members cm join public.companies c on c.id=cm.company_id
     where cm.user_id=p.user_id)
 )), '[]'::jsonb)
 from public.user_profiles p where private.can_read_friend_identity(p.user_id)
$$;
revoke all on function private.sko_friend_public_profiles() from public, anon;
grant execute on function private.sko_friend_public_profiles() to authenticated;
create or replace function public.sko_friend_public_profiles()
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.sko_friend_public_profiles()
$$;
revoke all on function public.sko_friend_public_profiles() from public, anon;
grant execute on function public.sko_friend_public_profiles() to authenticated;

-- Adds only friend reads; existing self/company photo rules remain unchanged.
create policy profile_photos_approved_friend_read on storage.objects
for select to authenticated using (
 bucket_id='profile-photos' and exists(
   select 1 from public.sko_friend_public_profiles() data,
   lateral jsonb_array_elements(data) profile
   where profile->>'avatar_storage_path'=storage.objects.name
 )
);
