-- Payroll list visibility and revision-based review confirmation.
-- Confirmation is valid only while reviewed_revision matches payroll_statements.revision.

alter table public.payroll_statements
  add column if not exists reviewed_revision integer,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;

create table if not exists public.payroll_worker_visibility (
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  visible_to_manager boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(company_id, worker_id)
);

alter table public.payroll_worker_visibility enable row level security;
revoke all on public.payroll_worker_visibility from anon, authenticated;

create or replace function public.payroll_review_workspace()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  statements jsonb;
  workers jsonb;
begin
  if uid is null then raise exception 'authentication required'; end if;
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm where cm.user_id=uid limit 1;
  if cid is null then raise exception 'company membership required'; end if;
  if role_text not in ('owner','admin','manager','viewer') then
    raise exception 'payroll list permission required';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',p.id,'worker_id',p.worker_id,'worker_name',w.name,
      'period_start',p.period_start,'period_end',p.period_end,
      'gross_pay',p.gross_pay,'deductions',p.deductions,'net_pay',p.net_pay,
      'detail',p.detail,'issued_at',p.issued_at,'revision',p.revision,
      'reviewed_revision',p.reviewed_revision,'reviewed_at',p.reviewed_at,
      'confirmed',p.reviewed_revision is not null and p.reviewed_revision=p.revision
    ) order by p.period_end desc,w.name
  ),'[]'::jsonb)
  into statements
  from public.payroll_statements p
  join public.workers w on w.id=p.worker_id and w.company_id=p.company_id
  left join public.payroll_worker_visibility v
    on v.company_id=p.company_id and v.worker_id=p.worker_id
  where p.company_id=cid
    and (
      role_text in ('owner','admin','viewer')
      or (role_text='manager' and coalesce(v.visible_to_manager,false))
    );

  if role_text in ('owner','admin') then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'worker_id',w.id,'worker_name',w.name,
        'visible_to_manager',coalesce(v.visible_to_manager,false)
      ) order by w.name
    ),'[]'::jsonb)
    into workers
    from public.workers w
    left join public.payroll_worker_visibility v
      on v.company_id=w.company_id and v.worker_id=w.id
    where w.company_id=cid and w.status='active';
  else
    workers:='[]'::jsonb;
  end if;

  return jsonb_build_object(
    'role',role_text,
    'can_manage_visibility',role_text in ('owner','admin'),
    'can_confirm',role_text='viewer',
    'statements',statements,
    'workers',workers
  );
end;
$function$;

revoke execute on function public.payroll_review_workspace() from public, anon;
grant execute on function public.payroll_review_workspace() to authenticated;

create or replace function public.set_payroll_worker_visibility(
  p_worker_id uuid,
  p_visible boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid:=auth.uid(); cid uuid;
begin
  select cm.company_id into cid
  from public.company_members cm
  where cm.user_id=uid and cm.role::text in ('owner','admin')
  limit 1;
  if cid is null then raise exception 'administrator permission required'; end if;
  if not exists(select 1 from public.workers w where w.id=p_worker_id and w.company_id=cid) then
    raise exception 'worker not found';
  end if;
  insert into public.payroll_worker_visibility(
    company_id,worker_id,visible_to_manager,updated_by,updated_at
  )
  values(cid,p_worker_id,coalesce(p_visible,false),uid,now())
  on conflict(company_id,worker_id) do update
  set visible_to_manager=excluded.visible_to_manager,
      updated_by=uid,
      updated_at=now();
end;
$function$;

revoke execute on function public.set_payroll_worker_visibility(uuid,boolean) from public, anon;
grant execute on function public.set_payroll_worker_visibility(uuid,boolean) to authenticated;

create or replace function public.confirm_payroll_review(
  p_period_start date,
  p_statement_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  role_text text;
  expected uuid[];
  normalized uuid[];
  changed integer;
begin
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm
  where cm.user_id=uid limit 1;
  if cid is null or role_text<>'viewer' then raise exception 'viewer permission required'; end if;
  if p_period_start is null then raise exception 'period required'; end if;

  select coalesce(array_agg(p.id order by p.id),'{}'::uuid[])
  into expected
  from public.payroll_statements p
  where p.company_id=cid
    and p.period_start=date_trunc('month',p_period_start)::date;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[])
  into normalized
  from unnest(coalesce(p_statement_ids,'{}'::uuid[])) x;

  if cardinality(expected)=0 then raise exception 'payroll statements not found'; end if;
  if expected is distinct from normalized then
    raise exception '全従業員の給与明細を確認してから確定してください';
  end if;

  update public.payroll_statements p
  set reviewed_revision=p.revision,
      reviewed_by=uid,
      reviewed_at=now(),
      updated_at=now()
  where p.company_id=cid and p.id=any(expected);

  get diagnostics changed=row_count;
  return changed;
end;
$function$;

revoke execute on function public.confirm_payroll_review(date,uuid[]) from public, anon;
grant execute on function public.confirm_payroll_review(date,uuid[]) to authenticated;

create or replace function public.my_payroll_review_statuses()
returns table(statement_id uuid, revision integer, confirmed boolean, reviewed_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'authentication required'; end if;
  return query
  select p.id,p.revision,
         (p.reviewed_revision is not null and p.reviewed_revision=p.revision),
         p.reviewed_at
  from public.payroll_statements p
  join public.workers w on w.id=p.worker_id and w.company_id=p.company_id
  where w.user_id=uid
  order by p.period_end desc;
end;
$function$;

revoke execute on function public.my_payroll_review_statuses() from public, anon;
grant execute on function public.my_payroll_review_statuses() to authenticated;
