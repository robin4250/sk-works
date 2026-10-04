create table if not exists public.payroll_manager_worker_visibility (
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  visible_to_manager boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(company_id,worker_id)
);

alter table public.payroll_manager_worker_visibility enable row level security;
revoke all on public.payroll_manager_worker_visibility from anon, authenticated;

create table if not exists public.payroll_statement_reviews (
  company_id uuid not null references public.companies(id) on delete cascade,
  statement_id uuid not null references public.payroll_statements(id) on delete cascade,
  reviewer_id uuid not null,
  checked_revision integer,
  checked_at timestamptz,
  confirmed_revision integer,
  confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(statement_id,reviewer_id)
);

create index if not exists payroll_statement_reviews_company_reviewer_idx
  on public.payroll_statement_reviews(company_id,reviewer_id);

alter table public.payroll_statement_reviews enable row level security;
revoke all on public.payroll_statement_reviews from anon, authenticated;

create or replace function private.payroll_review_workspace(p_period_start date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  v_period_start date:=coalesce(
    p_period_start,
    date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
  );
  result jsonb;
begin
  if uid is null then raise exception 'ログインが必要です'; end if;

  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null then raise exception '会社への所属が必要です'; end if;
  if role_text not in ('owner','admin','manager','viewer') then
    raise exception '給料一覧を閲覧する権限がありません';
  end if;

  select jsonb_build_object(
    'role',role_text,
    'is_admin',role_text in ('owner','admin'),
    'can_confirm',role_text='viewer',
    'period_start',v_period_start,
    'company_name',(select c.name from public.companies c where c.id=cid),
    'workers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',w.id,
        'name',w.name,
        'visible_to_manager',coalesce(v.visible_to_manager,false)
      ) order by w.name)
      from public.workers w
      left join public.payroll_manager_worker_visibility v
        on v.company_id=w.company_id and v.worker_id=w.id
      where w.company_id=cid
        and w.status='active'
        and w.affiliation::text='employee'
    ),'[]'::jsonb),
    'statements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',ps.id,
        'worker_id',ps.worker_id,
        'worker_name',w.name,
        'period_start',ps.period_start,
        'period_end',ps.period_end,
        'gross_pay',ps.gross_pay+coalesce(adj.additions_yen,0),
        'deductions',ps.deductions+coalesce(adj.deductions_yen,0),
        'net_pay',ps.gross_pay+coalesce(adj.additions_yen,0)-ps.deductions-coalesce(adj.deductions_yen,0),
        'detail',coalesce(ps.detail,'{}'::jsonb)||coalesce(adj.adjustment_detail,'{}'::jsonb),
        'revision',ps.revision,
        'workflow_state',ps.workflow_state,
        'review_checked',coalesce(rv.checked_revision=ps.revision,false),
        'review_confirmed',exists(
          select 1 from public.payroll_statement_reviews rr
          where rr.statement_id=ps.id
            and rr.confirmed_revision=ps.revision
            and rr.confirmed_at is not null
        ),
        'reviewer_confirmed',coalesce(rv.confirmed_revision=ps.revision,false)
      ) order by w.name)
      from public.payroll_statements ps
      join public.workers w
        on w.id=ps.worker_id and w.company_id=ps.company_id
      left join public.payroll_manager_worker_visibility v
        on v.company_id=ps.company_id and v.worker_id=ps.worker_id
      left join public.payroll_statement_reviews rv
        on rv.statement_id=ps.id and rv.reviewer_id=uid
      left join lateral (
        with active as (
          select a.label_snapshot,a.direction,a.amount_yen
          from public.payroll_adjustments a
          where a.company_id=ps.company_id
            and a.worker_id=ps.worker_id
            and a.effective_date between ps.period_start and ps.period_end
            and a.cancelled_at is null
        ),
        totals as (
          select
            coalesce(sum(case when direction='addition' then amount_yen else 0 end),0)::integer additions_yen,
            coalesce(sum(case when direction='deduction' then amount_yen else 0 end),0)::integer deductions_yen
          from active
        ),
        grouped as (
          select label_snapshot,
            sum(case when direction='addition' then amount_yen else -amount_yen end)::integer signed_total
          from active
          group by label_snapshot
        )
        select t.additions_yen,t.deductions_yen,
          coalesce(
            (select jsonb_object_agg(g.label_snapshot,g.signed_total) from grouped g),
            '{}'::jsonb
          ) adjustment_detail
        from totals t
      ) adj on true
      where ps.company_id=cid
        and ps.period_start=v_period_start
        and w.affiliation::text='employee'
        and (
          role_text in ('owner','admin','viewer')
          or (role_text='manager' and coalesce(v.visible_to_manager,false))
        )
    ),'[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

create or replace function public.payroll_review_workspace(p_period_start date default null)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  select private.payroll_review_workspace(p_period_start)
$function$;

revoke execute on function public.payroll_review_workspace(date) from public,anon;
grant execute on function public.payroll_review_workspace(date) to authenticated;

create or replace function private.set_payroll_manager_worker_visibility(
  p_worker_id uuid,
  p_visible boolean
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
begin
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null or role_text not in ('owner','admin') then
    raise exception '管理者のみ変更できます';
  end if;

  if not exists(
    select 1 from public.workers w
    where w.id=p_worker_id
      and w.company_id=cid
      and w.affiliation::text='employee'
  ) then
    raise exception '従業員が見つかりません';
  end if;

  insert into public.payroll_manager_worker_visibility(
    company_id,worker_id,visible_to_manager,updated_at
  )
  values(cid,p_worker_id,coalesce(p_visible,false),now())
  on conflict(company_id,worker_id) do update
  set visible_to_manager=excluded.visible_to_manager,
      updated_at=now();
end;
$function$;

create or replace function public.set_payroll_manager_worker_visibility(
  p_worker_id uuid,
  p_visible boolean
)
returns void
language sql
security invoker
set search_path=''
as $function$
  select private.set_payroll_manager_worker_visibility(p_worker_id,p_visible)
$function$;

revoke execute on function public.set_payroll_manager_worker_visibility(uuid,boolean)
  from public,anon;
grant execute on function public.set_payroll_manager_worker_visibility(uuid,boolean)
  to authenticated;

create or replace function private.set_payroll_review_check(
  p_statement_id uuid,
  p_revision integer,
  p_checked boolean
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  current_revision integer;
  statement_cid uuid;
begin
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null or role_text<>'viewer' then
    raise exception '閲覧者のみ確認チェックを変更できます';
  end if;

  select ps.company_id,ps.revision into statement_cid,current_revision
  from public.payroll_statements ps
  where ps.id=p_statement_id;

  if statement_cid is distinct from cid or current_revision is null then
    raise exception '給与明細が見つかりません';
  end if;

  if current_revision is distinct from p_revision then
    raise exception '給与明細が更新されています。一覧を再読み込みしてください';
  end if;

  insert into public.payroll_statement_reviews(
    company_id,statement_id,reviewer_id,
    checked_revision,checked_at,
    confirmed_revision,confirmed_at,updated_at
  )
  values(
    cid,p_statement_id,uid,
    case when p_checked then current_revision end,
    case when p_checked then now() end,
    null,null,now()
  )
  on conflict(statement_id,reviewer_id) do update
  set checked_revision=case when p_checked then current_revision end,
      checked_at=case when p_checked then now() end,
      confirmed_revision=null,
      confirmed_at=null,
      updated_at=now();
end;
$function$;

create or replace function public.set_payroll_review_check(
  p_statement_id uuid,
  p_revision integer,
  p_checked boolean
)
returns void
language sql
security invoker
set search_path=''
as $function$
  select private.set_payroll_review_check(p_statement_id,p_revision,p_checked)
$function$;

revoke execute on function public.set_payroll_review_check(uuid,integer,boolean)
  from public,anon;
grant execute on function public.set_payroll_review_check(uuid,integer,boolean)
  to authenticated;

create or replace function private.finalize_payroll_review(p_period_start date)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  missing_count integer;
  statement_count integer;
begin
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid
  limit 1;

  if cid is null or role_text<>'viewer' then
    raise exception '閲覧者のみ最終確定できます';
  end if;

  select count(*) into statement_count
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  where ps.company_id=cid
    and ps.period_start=p_period_start
    and w.affiliation::text='employee';

  if statement_count=0 then
    raise exception '確認対象の給与明細がありません';
  end if;

  select count(*) into missing_count
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  left join public.payroll_statement_reviews rv
    on rv.statement_id=ps.id and rv.reviewer_id=uid
  where ps.company_id=cid
    and ps.period_start=p_period_start
    and w.affiliation::text='employee'
    and rv.checked_revision is distinct from ps.revision;

  if missing_count>0 then
    raise exception '全従業員の給与明細を確認してから確定してください';
  end if;

  update public.payroll_statement_reviews rv
  set confirmed_revision=ps.revision,
      confirmed_at=now(),
      updated_at=now()
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  where rv.statement_id=ps.id
    and rv.reviewer_id=uid
    and ps.company_id=cid
    and ps.period_start=p_period_start
    and w.affiliation::text='employee'
    and rv.checked_revision=ps.revision;
end;
$function$;

create or replace function public.finalize_payroll_review(p_period_start date)
returns void
language sql
security invoker
set search_path=''
as $function$
  select private.finalize_payroll_review(p_period_start)
$function$;

revoke execute on function public.finalize_payroll_review(date)
  from public,anon;
grant execute on function public.finalize_payroll_review(date)
  to authenticated;

create or replace function private.my_payroll_review_statuses()
returns table(statement_id uuid,revision integer,review_confirmed boolean)
language sql
stable
security definer
set search_path=''
as $function$
  select
    ps.id,
    ps.revision,
    exists(
      select 1
      from public.payroll_statement_reviews r
      where r.statement_id=ps.id
        and r.confirmed_revision=ps.revision
        and r.confirmed_at is not null
    )
  from public.payroll_statements ps
  join public.workers w
    on w.id=ps.worker_id and w.company_id=ps.company_id
  where w.user_id=auth.uid()
  order by ps.period_end desc
$function$;

create or replace function public.my_payroll_review_statuses()
returns table(statement_id uuid,revision integer,review_confirmed boolean)
language sql
stable
security invoker
set search_path=''
as $function$
  select * from private.my_payroll_review_statuses()
$function$;

revoke execute on function public.my_payroll_review_statuses()
  from public,anon;
grant execute on function public.my_payroll_review_statuses()
  to authenticated;
