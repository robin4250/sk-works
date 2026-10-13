create or replace function private.connected_parent_receive_code(
  p_parent_company_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  c uuid;
  token uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  if not exists(
    select 1 from private.company_connections cc
    where cc.child_company_id=c
      and cc.parent_company_id=p_parent_company_id
      and cc.status='accepted'
  ) then
    raise exception '接続済みの親会社を選択してください。';
  end if;
  insert into private.document_receive_codes(
    company_id,created_by,expires_at
  )
  values(
    p_parent_company_id,
    auth.uid(),
    now()+interval '10 minutes'
  )
  returning code into token;
  return token;
end
$$;

create or replace function public.connected_parent_receive_code(
  p_parent_company_id uuid
)
returns uuid
language sql
set search_path=''
as $$ select private.connected_parent_receive_code(p_parent_company_id) $$;

revoke all on function public.connected_parent_receive_code(uuid)
from public,anon;
grant execute on function public.connected_parent_receive_code(uuid)
to authenticated;
