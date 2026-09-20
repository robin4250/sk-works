-- Run against the production project to verify pre-device security invariants.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('public', p.oid, 'EXECUTE')
      )
  ) then
    raise exception 'SECURITY DEFINER function is executable by anon or PUBLIC';
  end if;

  if has_table_privilege('anon', 'public.user_secondary_credentials', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.user_secondary_credentials', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'user_secondary_credentials must not be directly accessible';
  end if;

  if has_table_privilege('anon', 'public.line_webhook_events', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.line_webhook_events', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'line_webhook_events must not be directly accessible';
  end if;

  if position('failed_attempts + 1 >= 5' in pg_get_functiondef('public.verify_secondary_password(text)'::regprocedure)) = 0 then
    raise exception 'secondary-password five-attempt lock contract missing';
  end if;

  if position('requester cannot approve own request' in pg_get_functiondef('public.decide_daily_report_edit(uuid,text)'::regprocedure)) = 0 then
    raise exception 'daily-report self-approval protection missing';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='daily_report_edit_requests'
      and column_name='approvals_required'
      and column_default::text like '%2%'
  ) then
    raise exception 'daily-report two-approval default missing';
  end if;
end
$$;

select 'SKO pre-device database security assertions passed' as result;
