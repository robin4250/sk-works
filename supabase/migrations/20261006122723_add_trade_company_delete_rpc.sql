create or replace function private.delete_trade_company(
  p_trade_company_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  cid uuid;
  deleted_id uuid;
begin
  cid := private.current_company_admin_id();
  if cid is null then
    raise exception '管理者のみ操作できます。';
  end if;

  delete from public.trade_companies
  where id = p_trade_company_id
    and company_id = cid
  returning id into deleted_id;

  if deleted_id is null then
    raise exception '取引会社が見つかりません。';
  end if;
end
$$;

create or replace function public.delete_trade_company(
  p_trade_company_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.delete_trade_company(p_trade_company_id)
$$;

revoke all on function private.delete_trade_company(uuid)
from public, anon, authenticated;

revoke all on function public.delete_trade_company(uuid)
from public, anon;

grant execute on function public.delete_trade_company(uuid)
to authenticated;
