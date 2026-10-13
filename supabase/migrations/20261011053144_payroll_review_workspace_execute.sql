-- Restore the INVOKER wrapper's existing actor-scoped delegate, not table access.
begin;
do $$
begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.payroll_review_workspace(date)') and md5(prosrc)='a955dcbe1f15dfb56d7fc795b4117ac5' and not prosecdef and proconfig=array['search_path=""'])
 or not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_review_workspace(date)') and md5(prosrc)='d006962129b4f0cc4e958370f04308bf' and prosecdef and proconfig=array['search_path=""'])
 or not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_live_review_workspace(date)') and md5(prosrc)='fa27af8bdff62e3ab2223263d05add61' and prosecdef and proconfig=array['search_path=""']) then
  raise exception 'payroll workspace delegate prerequisite differs';
 end if;
end $$;
grant execute on function private.payroll_review_workspace(date) to authenticated;
commit;
