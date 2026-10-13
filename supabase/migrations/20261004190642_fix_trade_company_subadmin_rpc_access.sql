-- Mirrors production migration 20261004190642.
-- Allow sub administrators (manager) to use the trade-company workspace.
-- Keep private helpers non-callable from app roles and expose only authenticated
-- public RPC wrappers with explicit empty search_path inherited from definitions.

create or replace function private.current_company_admin_id()
returns uuid
language sql
stable
security definer
set search_path=''
as $$
  select cm.company_id
  from public.company_members cm
  where cm.user_id=auth.uid()
    and cm.role::text in ('owner','admin','manager')
  limit 1
$$;

revoke all on function private.current_company_admin_id()
from public,anon,authenticated;

alter function public.sync_trade_company_directory() security definer;
alter function public.trade_company_workspace() security definer;
alter function public.save_trade_company(uuid,text,text,text,text,text,text,text,text) security definer;
alter function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) security definer;
alter function public.trade_company_link_candidates(uuid) security definer;
alter function public.confirm_trade_company_link(uuid,uuid) security definer;
alter function public.trade_company_calculation_conflicts(uuid) security definer;
alter function public.select_site_calculation_source(uuid,text,uuid,text) security definer;

revoke all on function public.sync_trade_company_directory() from public,anon;
revoke all on function public.trade_company_workspace() from public,anon;
revoke all on function public.save_trade_company(uuid,text,text,text,text,text,text,text,text) from public,anon;
revoke all on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) from public,anon;
revoke all on function public.trade_company_link_candidates(uuid) from public,anon;
revoke all on function public.confirm_trade_company_link(uuid,uuid) from public,anon;
revoke all on function public.trade_company_calculation_conflicts(uuid) from public,anon;
revoke all on function public.select_site_calculation_source(uuid,text,uuid,text) from public,anon;

grant execute on function public.sync_trade_company_directory() to authenticated;
grant execute on function public.trade_company_workspace() to authenticated;
grant execute on function public.save_trade_company(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.save_trade_company_contract(uuid,text,integer,integer,integer,numeric,integer) to authenticated;
grant execute on function public.trade_company_link_candidates(uuid) to authenticated;
grant execute on function public.confirm_trade_company_link(uuid,uuid) to authenticated;
grant execute on function public.trade_company_calculation_conflicts(uuid) to authenticated;
grant execute on function public.select_site_calculation_source(uuid,text,uuid,text) to authenticated;
