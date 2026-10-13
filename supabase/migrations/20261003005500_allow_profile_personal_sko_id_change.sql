create or replace function private.change_personal_sko_id(p_sko_id text)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user uuid:=auth.uid();
  v_id text:=upper(trim(coalesce(p_sko_id,'')));
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if v_id !~ '^SKO-[A-Z0-9]{4,20}$' then
    raise exception 'SKO IDはSKO-に続けて英数字4〜20文字で入力してください';
  end if;

  begin
    insert into private.personal_sko_ids(user_id,sko_id)
    values(v_user,v_id)
    on conflict(user_id) do update set sko_id=excluded.sko_id;
  exception when unique_violation then
    raise exception 'このSKO IDはすでに使用されています';
  end;

  return v_id;
end;
$$;

create or replace function public.change_personal_sko_id(p_sko_id text)
returns text
language sql
set search_path to ''
as $$
  select private.change_personal_sko_id(p_sko_id)
$$;

revoke all on function public.change_personal_sko_id(text) from public;
grant execute on function public.change_personal_sko_id(text) to authenticated;
