-- Staged OFF. Restriction rows are an existing deployed deletion-flow contract.
-- Do not create, mutate or broaden access to the deletion restriction table.
do $$
declare r regclass:=to_regclass('private.account_deletion_access_restrictions');
begin
 if r is null then raise exception 'existing account deletion restrictions are required'; end if;
 if not exists(select 1 from pg_class where oid=r and relkind='r' and relrowsecurity
  and relowner=(select oid from pg_roles where rolname=current_user)) then
  raise exception 'account deletion restriction owner/RLS contract differs';
 end if;
 if (select count(*) from pg_attribute where attrelid=r and attnum>0 and not attisdropped)<>3
  or not exists(select 1 from pg_attribute where attrelid=r and attname='user_id' and atttypid='uuid'::regtype and attnotnull and not attisdropped)
  or not exists(select 1 from pg_attribute where attrelid=r and attname='job_id' and atttypid='uuid'::regtype and attnotnull and not attisdropped)
  or not exists(select 1 from pg_attribute where attrelid=r and attname='restricted_at' and atttypid='timestamptz'::regtype and attnotnull and not attisdropped) then
  raise exception 'account deletion restriction columns differ';
 end if;
 if has_table_privilege('anon',r,'SELECT') or has_table_privilege('authenticated',r,'SELECT') then
  raise exception 'account deletion restriction client read access differs';
 end if;
 if to_regprocedure('private.source_notification_recipient_eligible(uuid,uuid)') is null then
  raise exception 'source notification business recipient contract is required';
 end if;
end $$;

create or replace function private.source_notification_recipient_eligible(p_company_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_company_id is not null and p_user_id is not null
 and not exists(select 1 from private.account_deletion_access_restrictions where user_id=p_user_id)
 and exists(
  select 1 from public.company_members m where m.company_id=p_company_id and m.user_id=p_user_id
  and (exists(select 1 from public.workers w where w.company_id=p_company_id and w.user_id=p_user_id and w.status='active')
   or (m.role::text in ('owner','admin') and not exists(select 1 from public.workers w where w.company_id=p_company_id and w.user_id=p_user_id)))
 )
$$;
revoke all on function private.source_notification_recipient_eligible(uuid,uuid) from public,anon,authenticated;
