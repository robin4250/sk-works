create table if not exists private.personal_sko_ids (
  user_id uuid primary key,
  sko_id text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists private.sko_friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null,
  recipient_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (requester_id, recipient_id),
  check (requester_id <> recipient_id)
);

create table if not exists private.sko_friends (
  user_a uuid not null,
  user_b uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a <> user_b)
);

create or replace function private.ensure_personal_sko_id()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id text;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select s.sko_id into v_id from private.personal_sko_ids s where s.user_id=v_user;
  if v_id is not null then return v_id; end if;
  loop
    v_id := 'SKO-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into private.personal_sko_ids(user_id,sko_id) values(v_user,v_id);
      return v_id;
    exception when unique_violation then
      select s.sko_id into v_id from private.personal_sko_ids s where s.user_id=v_user;
      if v_id is not null then return v_id; end if;
    end;
  end loop;
end
$$;

create or replace function private.search_personal_sko_id(p_sko_id text)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_target uuid;
  v_id text := upper(trim(coalesce(p_sko_id,'')));
  v_name text;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  if v_id='' then return null; end if;
  select s.user_id into v_target from private.personal_sko_ids s where s.sko_id=v_id limit 1;
  if v_target is null or v_target=v_user then return null; end if;
  select coalesce(nullif(p.display_name,''),'SKOユーザー')
    into v_name from public.user_profiles p where p.user_id=v_target limit 1;
  return jsonb_build_object(
    'user_id',v_target,
    'sko_id',v_id,
    'display_name',coalesce(v_name,'SKOユーザー')
  );
end
$$;

create or replace function private.send_sko_friend_request(p_sko_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_target uuid;
  v_request uuid;
  v_a uuid;
  v_b uuid;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select s.user_id into v_target
  from private.personal_sko_ids s
  where s.sko_id=upper(trim(coalesce(p_sko_id,''))) limit 1;
  if v_target is null or v_target=v_user then raise exception 'SKO IDを確認してください'; end if;

  v_a:=least(v_user,v_target);
  v_b:=greatest(v_user,v_target);
  if exists(select 1 from private.sko_friends f where f.user_a=v_a and f.user_b=v_b) then
    raise exception 'すでに友達です';
  end if;
  if exists(
    select 1 from private.sko_friend_requests r
    where r.requester_id=v_target and r.recipient_id=v_user and r.status='pending'
  ) then
    raise exception '相手から申請が届いています';
  end if;

  insert into private.sko_friend_requests(
    requester_id,recipient_id,status,created_at,responded_at
  ) values(v_user,v_target,'pending',now(),null)
  on conflict(requester_id,recipient_id)
  do update set status='pending',created_at=now(),responded_at=null
  returning id into v_request;
  return v_request;
end
$$;

create or replace function private.sko_friend_workspace()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_sko_id text;
  v_incoming jsonb;
  v_outgoing jsonb;
  v_friends jsonb;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  v_sko_id:=private.ensure_personal_sko_id();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'user_id',r.requester_id,
    'display_name',coalesce(nullif(p.display_name,''),'SKOユーザー'),
    'sko_id',s.sko_id,'created_at',r.created_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_incoming
  from private.sko_friend_requests r
  left join public.user_profiles p on p.user_id=r.requester_id
  left join private.personal_sko_ids s on s.user_id=r.requester_id
  where r.recipient_id=v_user and r.status='pending';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'user_id',r.recipient_id,
    'display_name',coalesce(nullif(p.display_name,''),'SKOユーザー'),
    'sko_id',s.sko_id,'created_at',r.created_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_outgoing
  from private.sko_friend_requests r
  left join public.user_profiles p on p.user_id=r.recipient_id
  left join private.personal_sko_ids s on s.user_id=r.recipient_id
  where r.requester_id=v_user and r.status='pending';

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',x.friend_id,
    'display_name',coalesce(nullif(p.display_name,''),'SKOユーザー'),
    'sko_id',s.sko_id,'created_at',x.created_at
  ) order by p.display_name),'[]'::jsonb)
  into v_friends
  from (
    select case when f.user_a=v_user then f.user_b else f.user_a end friend_id,
           f.created_at
    from private.sko_friends f
    where f.user_a=v_user or f.user_b=v_user
  ) x
  left join public.user_profiles p on p.user_id=x.friend_id
  left join private.personal_sko_ids s on s.user_id=x.friend_id;

  return jsonb_build_object(
    'my_sko_id',v_sko_id,
    'incoming',v_incoming,
    'outgoing',v_outgoing,
    'friends',v_friends
  );
end
$$;

create or replace function private.respond_sko_friend_request(
  p_request_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_requester uuid;
  v_a uuid;
  v_b uuid;
begin
  if v_user is null then raise exception 'ログインが必要です'; end if;
  select r.requester_id into v_requester
  from private.sko_friend_requests r
  where r.id=p_request_id and r.recipient_id=v_user and r.status='pending'
  for update;
  if v_requester is null then raise exception '友達申請を確認できません'; end if;

  update private.sko_friend_requests
  set status=case when p_accept then 'accepted' else 'rejected' end,
      responded_at=now()
  where id=p_request_id;

  if p_accept then
    v_a:=least(v_user,v_requester);
    v_b:=greatest(v_user,v_requester);
    insert into private.sko_friends(user_a,user_b)
    values(v_a,v_b) on conflict do nothing;
  end if;
end
$$;

create or replace function private.remove_sko_friend(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_a uuid;
  v_b uuid;
begin
  if v_user is null or p_user is null or p_user=v_user then
    raise exception '対象を確認してください';
  end if;
  v_a:=least(v_user,p_user);
  v_b:=greatest(v_user,p_user);
  delete from private.sko_friends where user_a=v_a and user_b=v_b;
end
$$;

create or replace function public.ensure_personal_sko_id()
returns text language sql set search_path=''
as $$ select private.ensure_personal_sko_id() $$;

create or replace function public.search_personal_sko_id(p_sko_id text)
returns jsonb language sql set search_path=''
as $$ select private.search_personal_sko_id(p_sko_id) $$;

create or replace function public.send_sko_friend_request(p_sko_id text)
returns uuid language sql set search_path=''
as $$ select private.send_sko_friend_request(p_sko_id) $$;

create or replace function public.sko_friend_workspace()
returns jsonb language sql set search_path=''
as $$ select private.sko_friend_workspace() $$;

create or replace function public.respond_sko_friend_request(
  p_request_id uuid,
  p_accept boolean
)
returns void language sql set search_path=''
as $$ select private.respond_sko_friend_request(p_request_id,p_accept) $$;

create or replace function public.remove_sko_friend(p_user uuid)
returns void language sql set search_path=''
as $$ select private.remove_sko_friend(p_user) $$;

revoke all on function public.ensure_personal_sko_id() from public, anon;
revoke all on function public.search_personal_sko_id(text) from public, anon;
revoke all on function public.send_sko_friend_request(text) from public, anon;
revoke all on function public.sko_friend_workspace() from public, anon;
revoke all on function public.respond_sko_friend_request(uuid,boolean) from public, anon;
revoke all on function public.remove_sko_friend(uuid) from public, anon;

grant execute on function public.ensure_personal_sko_id() to authenticated;
grant execute on function public.search_personal_sko_id(text) to authenticated;
grant execute on function public.send_sko_friend_request(text) to authenticated;
grant execute on function public.sko_friend_workspace() to authenticated;
grant execute on function public.respond_sko_friend_request(uuid,boolean) to authenticated;
grant execute on function public.remove_sko_friend(uuid) to authenticated;
