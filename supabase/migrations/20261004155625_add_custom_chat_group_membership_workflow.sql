-- Mirrors production migration 20261004155625.
-- Custom friend-based chat groups use explicit participants, approval invites,
-- member leave/removal, and automatic cleanup when the last member leaves.

create table if not exists private.chat_group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.communication_groups(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  inviter_user_id uuid not null references auth.users(id) on delete cascade,
  invitee_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (group_id, invitee_user_id, status)
);

revoke all on table private.chat_group_invites from public, anon, authenticated;

create or replace function private.create_custom_chat_group(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_company uuid; v_group uuid; v_name text := btrim(coalesce(p_name,''));
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if v_name = '' then raise exception 'グループ名を入力してください'; end if;
  select cm.company_id into v_company from public.company_members cm where cm.user_id=v_user limit 1;
  if v_company is null then raise exception '会社情報が見つかりません'; end if;
  insert into public.communication_groups(company_id,name,group_type,participants_only,created_by,last_activity_at)
  values(v_company,v_name,'company',true,v_user,now()) returning id into v_group;
  insert into public.communication_group_members(group_id,company_id,user_id)
  values(v_group,v_company,v_user) on conflict do nothing;
  return v_group;
end $$;

create or replace function public.create_custom_chat_group(p_name text)
returns uuid language sql set search_path = '' as $$ select private.create_custom_chat_group(p_name) $$;
revoke execute on function public.create_custom_chat_group(text) from public, anon;
grant execute on function public.create_custom_chat_group(text) to authenticated;

create or replace function private.invite_friend_to_chat_group(p_group_id uuid,p_friend_user_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_company uuid; v_invite uuid; v_group_name text; v_sender_name text;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if p_group_id is null or p_friend_user_id is null then raise exception '招待先を確認してください'; end if;
  if p_friend_user_id=v_user then raise exception '自分自身は招待できません'; end if;

  select cg.company_id,cg.name into v_company,v_group_name
  from public.communication_groups cg
  where cg.id=p_group_id and cg.participants_only=true
    and exists(select 1 from public.communication_group_members gm where gm.group_id=cg.id and gm.user_id=v_user);
  if v_company is null then raise exception 'このグループへ招待できません'; end if;

  if not exists(
    select 1 from private.sko_friends f
    where (f.user_a=v_user and f.user_b=p_friend_user_id)
       or (f.user_b=v_user and f.user_a=p_friend_user_id)
  ) then raise exception '友達だけを招待できます'; end if;

  if exists(select 1 from public.communication_group_members gm where gm.group_id=p_group_id and gm.user_id=p_friend_user_id)
  then raise exception 'すでに参加しています'; end if;

  update private.chat_group_invites set status='cancelled',responded_at=now()
  where group_id=p_group_id and invitee_user_id=p_friend_user_id and status='pending';

  insert into private.chat_group_invites(group_id,company_id,inviter_user_id,invitee_user_id)
  values(p_group_id,v_company,v_user,p_friend_user_id) returning id into v_invite;

  select coalesce(nullif(up.display_name,''),'SKOユーザー') into v_sender_name
  from public.user_profiles up where up.user_id=v_user;

  insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)
  values(v_company,p_friend_user_id,'chat_group_invite','グループチャット招待',
    coalesce(v_sender_name,'SKOユーザー') || 'さんから「' || coalesce(v_group_name,'グループ') || '」へ招待されました',
    'chat_group_invite',v_invite);
  return v_invite;
end $$;

create or replace function public.invite_friend_to_chat_group(p_group_id uuid,p_friend_user_id uuid)
returns uuid language sql set search_path = '' as $$ select private.invite_friend_to_chat_group(p_group_id,p_friend_user_id) $$;
revoke execute on function public.invite_friend_to_chat_group(uuid,uuid) from public, anon;
grant execute on function public.invite_friend_to_chat_group(uuid,uuid) to authenticated;

create or replace function private.my_chat_group_invites()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_result jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,'group_id',i.group_id,'group_name',g.name,'inviter_user_id',i.inviter_user_id,
    'inviter_name',coalesce(nullif(p.display_name,''),'SKOユーザー'),'created_at',i.created_at
  ) order by i.created_at desc),'[]'::jsonb)
  into v_result
  from private.chat_group_invites i
  join public.communication_groups g on g.id=i.group_id
  left join public.user_profiles p on p.user_id=i.inviter_user_id
  where i.invitee_user_id=v_user and i.status='pending';
  return v_result;
end $$;

create or replace function public.my_chat_group_invites()
returns jsonb language sql set search_path = '' as $$ select private.my_chat_group_invites() $$;
revoke execute on function public.my_chat_group_invites() from public, anon;
grant execute on function public.my_chat_group_invites() to authenticated;

create or replace function private.respond_chat_group_invite(p_invite_id uuid,p_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_invite private.chat_group_invites%rowtype;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select * into v_invite from private.chat_group_invites
  where id=p_invite_id and invitee_user_id=v_user and status='pending' for update;
  if v_invite.id is null then raise exception '招待が見つかりません'; end if;
  if p_accept then
    insert into public.communication_group_members(group_id,company_id,user_id)
    values(v_invite.group_id,v_invite.company_id,v_user) on conflict do nothing;
    update private.chat_group_invites set status='accepted',responded_at=now() where id=p_invite_id;
  else
    update private.chat_group_invites set status='declined',responded_at=now() where id=p_invite_id;
  end if;
  return v_invite.group_id;
end $$;

create or replace function public.respond_chat_group_invite(p_invite_id uuid,p_accept boolean)
returns uuid language sql set search_path = '' as $$ select private.respond_chat_group_invite(p_invite_id,p_accept) $$;
revoke execute on function public.respond_chat_group_invite(uuid,boolean) from public, anon;
grant execute on function public.respond_chat_group_invite(uuid,boolean) to authenticated;

create or replace function private.leave_custom_chat_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_remaining integer;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if not exists(
    select 1 from public.communication_groups g
    join public.communication_group_members gm on gm.group_id=g.id
    where g.id=p_group_id and g.participants_only=true and gm.user_id=v_user
  ) then raise exception '参加中のグループではありません'; end if;

  delete from public.communication_group_members where group_id=p_group_id and user_id=v_user;
  select count(*) into v_remaining from public.communication_group_members where group_id=p_group_id;
  if v_remaining=0 then delete from public.communication_groups where id=p_group_id; end if;
end $$;

create or replace function public.leave_custom_chat_group(p_group_id uuid)
returns void language sql set search_path = '' as $$ select private.leave_custom_chat_group(p_group_id) $$;
revoke execute on function public.leave_custom_chat_group(uuid) from public, anon;
grant execute on function public.leave_custom_chat_group(uuid) to authenticated;

create or replace function private.remove_custom_chat_group_member(p_group_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_creator uuid;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select created_by into v_creator from public.communication_groups where id=p_group_id and participants_only=true;
  if v_creator is null then raise exception '対象グループが見つかりません'; end if;
  if v_user<>v_creator and not private.can_manage_communication_group(p_group_id)
  then raise exception 'メンバーを追放する権限がありません'; end if;
  if p_user_id=v_user then raise exception '自分の脱退は脱退ボタンを使用してください'; end if;
  delete from public.communication_group_members where group_id=p_group_id and user_id=p_user_id;
end $$;

create or replace function public.remove_custom_chat_group_member(p_group_id uuid,p_user_id uuid)
returns void language sql set search_path = '' as $$ select private.remove_custom_chat_group_member(p_group_id,p_user_id) $$;
revoke execute on function public.remove_custom_chat_group_member(uuid,uuid) from public, anon;
grant execute on function public.remove_custom_chat_group_member(uuid,uuid) to authenticated;

create or replace function private.delete_custom_chat_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_creator uuid;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select created_by into v_creator from public.communication_groups where id=p_group_id and participants_only=true;
  if v_creator is null then raise exception '対象グループが見つかりません'; end if;
  if v_user<>v_creator and not private.can_manage_communication_group(p_group_id)
  then raise exception 'グループを削除する権限がありません'; end if;
  delete from public.communication_groups where id=p_group_id;
end $$;

create or replace function public.delete_custom_chat_group(p_group_id uuid)
returns void language sql set search_path = '' as $$ select private.delete_custom_chat_group(p_group_id) $$;
revoke execute on function public.delete_custom_chat_group(uuid) from public, anon;
grant execute on function public.delete_custom_chat_group(uuid) to authenticated;
