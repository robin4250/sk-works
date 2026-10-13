-- Mirrors production migration 20261004111520.
-- A viewer may confirm a month only after every employee statement is checked
-- at its current revision.

create or replace function private.confirm_payroll_review_month(p_period_start date)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  v_period_start date:=date_trunc('month',p_period_start)::date;
  expected_count integer;
  checked_count integer;
  changed integer;
begin
  if uid is null then raise exception 'ログインが必要です'; end if;
  if p_period_start is null then raise exception '対象月を確認してください'; end if;

  select cm.company_id,cm.role::text
  into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null or role_text<>'viewer' then
    raise exception '閲覧者のみ給与確認を確定できます';
  end if;

  select count(*)
  into expected_count
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  where ps.company_id=cid
    and ps.period_start=v_period_start
    and w.affiliation::text='employee';

  if expected_count=0 then
    raise exception 'この月の給与明細がありません';
  end if;

  select count(*)
  into checked_count
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  join public.payroll_statement_reviews r
    on r.statement_id=ps.id
   and r.reviewer_id=uid
   and r.checked_revision=ps.revision
  where ps.company_id=cid
    and ps.period_start=v_period_start
    and w.affiliation::text='employee';

  if checked_count<>expected_count then
    raise exception '全従業員の給与明細を確認してから確定してください';
  end if;

  update public.payroll_statement_reviews r
  set confirmed_revision=ps.revision,
      confirmed_at=now(),
      updated_at=now()
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  where r.statement_id=ps.id
    and r.reviewer_id=uid
    and ps.company_id=cid
    and ps.period_start=v_period_start
    and w.affiliation::text='employee'
    and r.checked_revision=ps.revision;

  get diagnostics changed=row_count;
  return changed;
end;
$function$;

create or replace function public.confirm_payroll_review_month(p_period_start date)
returns integer
language sql
set search_path = ''
as $function$
  select private.confirm_payroll_review_month(p_period_start)
$function$;

revoke execute on function public.confirm_payroll_review_month(date)
  from public, anon;
grant execute on function public.confirm_payroll_review_month(date)
  to authenticated;
