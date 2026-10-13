-- Restrict aggregate Master growth analytics to signed-in callers.
-- The function also performs a Master-role check internally.
revoke all on function public.get_master_growth_snapshot()
  from public, anon;
grant execute on function public.get_master_growth_snapshot()
  to authenticated;
