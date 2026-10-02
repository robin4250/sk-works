create table if not exists private.company_connections (
  id uuid primary key default gen_random_uuid(),
  parent_company_id uuid not null references public.companies(id) on delete cascade,
  child_company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','disabled')),
  requested_by uuid not null,
  responded_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(parent_company_id, child_company_id),
  check(parent_company_id <> child_company_id)
);

alter table private.company_connections enable row level security;

create index if not exists company_connections_child_status_idx
  on private.company_connections(child_company_id,status);
create index if not exists company_connections_parent_status_idx
  on private.company_connections(parent_company_id,status);

create or replace function private.company_connection_targets()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'connection_id',cc.id,
      'company_id',co.id,
      'company_name',co.name
    ) order by co.name)
    from private.company_connections cc
    join public.companies co on co.id=cc.parent_company_id
    where cc.child_company_id=c and cc.status='accepted'
  ),'[]'::jsonb);
end
$$;

create or replace function private.company_connection_inbox()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  return jsonb_build_object(
    'incoming',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cc.id,
        'child_company_id',cc.child_company_id,
        'child_company_name',co.name,
        'status',cc.status,
        'created_at',cc.created_at
      ) order by cc.created_at desc)
      from private.company_connections cc
      join public.companies co on co.id=cc.child_company_id
      where cc.parent_company_id=c and cc.status='pending'
    ),'[]'::jsonb),
    'outgoing',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cc.id,
        'parent_company_id',cc.parent_company_id,
        'parent_company_name',co.name,
        'status',cc.status,
        'created_at',cc.created_at
      ) order by cc.created_at desc)
      from private.company_connections cc
      join public.companies co on co.id=cc.parent_company_id
      where cc.child_company_id=c
    ),'[]'::jsonb)
  );
end
$$;

create or replace function private.request_company_connection(p_parent_company_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare c uuid; rid uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  if p_parent_company_id is null or p_parent_company_id=c then
    raise exception '接続先会社を確認してください。';
  end if;
  if not exists(select 1 from public.companies co where co.id=p_parent_company_id) then
    raise exception '接続先会社が見つかりません。';
  end if;
  insert into private.company_connections(
    parent_company_id,child_company_id,status,requested_by,responded_by,updated_at
  )
  values(p_parent_company_id,c,'pending',auth.uid(),null,now())
  on conflict(parent_company_id,child_company_id)
  do update set status='pending',requested_by=auth.uid(),responded_by=null,updated_at=now()
  returning id into rid;
  return rid;
end
$$;

create or replace function private.respond_company_connection(
  p_connection_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  update private.company_connections
  set status=case when p_accept then 'accepted' else 'rejected' end,
      responded_by=auth.uid(),
      updated_at=now()
  where id=p_connection_id and parent_company_id=c and status='pending';
  if not found then raise exception '接続申請を確認できません。'; end if;
end
$$;

create or replace function public.company_connection_targets()
returns jsonb language sql set search_path=''
as $$ select private.company_connection_targets() $$;

create or replace function public.company_connection_inbox()
returns jsonb language sql set search_path=''
as $$ select private.company_connection_inbox() $$;

create or replace function public.request_company_connection(p_parent_company_id uuid)
returns uuid language sql set search_path=''
as $$ select private.request_company_connection(p_parent_company_id) $$;

create or replace function public.respond_company_connection(
  p_connection_id uuid,
  p_accept boolean
)
returns void language sql set search_path=''
as $$ select private.respond_company_connection(p_connection_id,p_accept) $$;

revoke all on function public.company_connection_targets() from public,anon;
revoke all on function public.company_connection_inbox() from public,anon;
revoke all on function public.request_company_connection(uuid) from public,anon;
revoke all on function public.respond_company_connection(uuid,boolean) from public,anon;

grant execute on function public.company_connection_targets() to authenticated;
grant execute on function public.company_connection_inbox() to authenticated;
grant execute on function public.request_company_connection(uuid) to authenticated;
grant execute on function public.respond_company_connection(uuid,boolean) to authenticated;
