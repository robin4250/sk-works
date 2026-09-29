alter table public.communication_groups
  add column if not exists archived_at timestamptz;

create unique index if not exists one_site_chat_per_site
  on public.communication_groups(company_id, site_id)
  where group_type='site' and site_id is not null;

create or replace function private.ensure_site_chat(p_site_id uuid)
returns uuid
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  s public.sites%rowtype;
  gid uuid;
begin
  select * into s from public.sites where id=p_site_id;
  if not found then return null; end if;

  select id into gid
  from public.communication_groups
  where company_id=s.company_id
    and site_id=s.id
    and group_type='site'
  limit 1;

  if gid is null then
    begin
      insert into public.communication_groups(
        company_id,site_id,name,group_type,participants_only,created_by,archived_at
      ) values (
        s.company_id,s.id,s.name,'site',true,s.created_by,
        case when s.status='completed' then now() else null end
      )
      returning id into gid;
    exception when unique_violation then
      select id into gid
      from public.communication_groups
      where company_id=s.company_id
        and site_id=s.id
        and group_type='site'
      limit 1;
    end;
  else
    update public.communication_groups
    set name=s.name,
        participants_only=true,
        archived_at=case
          when s.status='completed' then coalesce(archived_at,now())
          else null
        end,
        updated_at=now()
    where id=gid;
  end if;

  return gid;
end;
$$;

create or replace function private.sync_site_chat_lifecycle()
returns trigger
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
begin
  perform private.ensure_site_chat(new.id);
  return new;
end;
$$;

drop trigger if exists sync_site_chat_lifecycle on public.sites;
create trigger sync_site_chat_lifecycle
after insert or update of name,status on public.sites
for each row execute function private.sync_site_chat_lifecycle();

create or replace function private.join_site_chat_for_worker(
  p_worker_id uuid,
  p_site_id uuid
)
returns void
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare
  uid uuid;
  cid uuid;
  gid uuid;
begin
  select w.user_id,w.company_id into uid,cid
  from public.workers w
  where w.id=p_worker_id
    and w.status='active';

  if uid is null or cid is null then return; end if;

  gid := private.ensure_site_chat(p_site_id);
  if gid is null then return; end if;

  if not exists(
    select 1 from public.communication_groups g
    where g.id=gid and g.company_id=cid
  ) then
    return;
  end if;

  insert into public.communication_group_members(group_id,company_id,user_id)
  values(gid,cid,uid)
  on conflict (group_id,user_id) do nothing;
end;
$$;

create or replace function private.attendance_join_site_chat()
returns trigger
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
begin
  perform private.join_site_chat_for_worker(new.worker_id,new.site_id);
  return new;
end;
$$;

drop trigger if exists attendance_join_site_chat on public.attendance_entries;
create trigger attendance_join_site_chat
after insert or update of worker_id,site_id on public.attendance_entries
for each row execute function private.attendance_join_site_chat();

create or replace function private.verification_join_site_chat()
returns trigger
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
begin
  if new.event_type='clock_in' then
    perform private.join_site_chat_for_worker(new.worker_id,new.site_id);
  end if;
  return new;
end;
$$;

drop trigger if exists verification_join_site_chat on public.attendance_verifications;
create trigger verification_join_site_chat
after insert on public.attendance_verifications
for each row execute function private.verification_join_site_chat();

create or replace function private.can_access_communication_group(p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_group_type text;
  v_role text;
  v_participants_only boolean;
begin
  if v_user_id is null or p_group_id is null then
    return false;
  end if;

  select cg.company_id,cg.group_type,cg.participants_only
  into v_company_id,v_group_type,v_participants_only
  from public.communication_groups cg
  where cg.id=p_group_id;

  if v_company_id is null then return false; end if;

  select cm.role::text into v_role
  from public.company_members cm
  where cm.company_id=v_company_id and cm.user_id=v_user_id
  limit 1;

  if v_role is null then return false; end if;

  if v_group_type='site'
     and v_role in ('owner','admin','manager') then
    return true;
  end if;

  if v_group_type='direct' or v_participants_only then
    return exists(
      select 1 from public.communication_group_members cgm
      where cgm.group_id=p_group_id
        and cgm.company_id=v_company_id
        and cgm.user_id=v_user_id
    );
  end if;

  if v_group_type='partner' then
    if v_role in ('owner','admin') then return true; end if;
    return exists(
      select 1 from public.member_feature_permissions mfp
      where mfp.company_id=v_company_id
        and mfp.user_id=v_user_id
        and mfp.can_manage_partner_chat=true
    );
  end if;

  return v_group_type='company';
end;
$$;

create or replace function private.chat_can_send(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select auth.uid() is not null
    and private.can_access_communication_group(p_group)
    and exists(
      select 1 from public.communication_groups g
      where g.id=p_group and g.archived_at is null
    )
    and not exists(
      select 1
      from public.communication_groups g
      join public.communication_group_members m on m.group_id=g.id
      where g.id=p_group
        and g.group_type='direct'
        and not private.chat_sender_visible(m.user_id)
    )
$$;

insert into public.communication_groups(
  company_id,site_id,name,group_type,participants_only,created_by,archived_at
)
select
  s.company_id,s.id,s.name,'site',true,s.created_by,
  case when s.status='completed' then now() else null end
from public.sites s
where not exists(
  select 1 from public.communication_groups g
  where g.company_id=s.company_id
    and g.site_id=s.id
    and g.group_type='site'
);

update public.communication_groups g
set participants_only=true,
    name=s.name,
    archived_at=case
      when s.status='completed' then coalesce(g.archived_at,now())
      else null
    end,
    updated_at=now()
from public.sites s
where g.site_id=s.id
  and g.company_id=s.company_id
  and g.group_type='site';

insert into public.communication_group_members(group_id,company_id,user_id)
select distinct g.id,w.company_id,w.user_id
from public.attendance_entries ae
join public.workers w on w.id=ae.worker_id
join public.communication_groups g
  on g.site_id=ae.site_id
 and g.company_id=ae.company_id
 and g.group_type='site'
where w.user_id is not null
on conflict (group_id,user_id) do nothing;

insert into public.communication_group_members(group_id,company_id,user_id)
select distinct g.id,w.company_id,w.user_id
from public.attendance_verifications av
join public.workers w on w.id=av.worker_id
join public.communication_groups g
  on g.site_id=av.site_id
 and g.company_id=av.company_id
 and g.group_type='site'
where av.event_type='clock_in'
  and w.user_id is not null
on conflict (group_id,user_id) do nothing;

revoke all on function private.ensure_site_chat(uuid) from public,anon,authenticated;
revoke all on function private.join_site_chat_for_worker(uuid,uuid) from public,anon,authenticated;
