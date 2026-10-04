-- Mirrors production migration 20261004162159.
-- Any member of an explicit participants-only custom group can remove
-- another member by long-press. Self-removal must use the leave action.

create or replace function private.remove_custom_chat_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if p_group_id is null or p_user_id is null then
    raise exception '対象メンバーを確認してください';
  end if;
  if p_user_id=v_user then
    raise exception '自分の脱退は脱退ボタンを使用してください';
  end if;

  if not exists(
    select 1
    from public.communication_groups g
    join public.communication_group_members me
      on me.group_id=g.id and me.user_id=v_user
    where g.id=p_group_id
      and g.participants_only=true
  ) then
    raise exception 'このグループのメンバーではありません';
  end if;

  if not exists(
    select 1
    from public.communication_group_members target
    where target.group_id=p_group_id
      and target.user_id=p_user_id
  ) then
    raise exception '対象メンバーが見つかりません';
  end if;

  delete from public.communication_group_members
  where group_id=p_group_id
    and user_id=p_user_id;
end
$$;

create or replace function public.remove_custom_chat_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language sql
set search_path = ''
as $$ select private.remove_custom_chat_group_member(p_group_id,p_user_id) $$;

revoke execute on function public.remove_custom_chat_group_member(uuid,uuid)
from public, anon;
grant execute on function public.remove_custom_chat_group_member(uuid,uuid)
to authenticated;
