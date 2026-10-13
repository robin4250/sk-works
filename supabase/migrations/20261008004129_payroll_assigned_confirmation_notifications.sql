-- Company payroll rules are the sole current source. Existing statement dates remain historical snapshots.
alter table public.companies add column if not exists payroll_payment_day integer,
 add column if not exists payroll_payment_month_offset integer not null default 1,
 add column if not exists payroll_closing_day integer not null default 31;
-- Preserve the legacy evidence; differing individual values are not overwritten.
alter table public.companies add column if not exists payroll_payment_day_migration jsonb;
update public.companies c set payroll_payment_day_migration=jsonb_build_object(
 'source','legacy worker payment_day','legacy_days',(select coalesce(jsonb_agg(distinct s.payment_day),'[]'::jsonb) from public.worker_payroll_settings s where s.company_id=c.id),
 'resolution',case when (select count(distinct s.payment_day) from public.worker_payroll_settings s where s.company_id=c.id)>1 then 'owner preference; legacy values and statement snapshots retained' else 'existing company-wide value or default25' end)
where payroll_payment_day is null;
-- Preserve one existing company-wide value; conflicting legacy entries use recorded owner preference.
update public.companies c set payroll_payment_day=coalesce(
 (select max(s.payment_day) from public.worker_payroll_settings s where s.company_id=c.id having count(distinct s.payment_day)=1),
 (select s.payment_day from public.worker_payroll_settings s join public.workers w on w.id=s.worker_id and w.company_id=s.company_id join public.company_members cm on cm.company_id=s.company_id and cm.user_id=w.user_id where s.company_id=c.id and cm.role::text='owner' order by w.id limit 1),25)
where payroll_payment_day is null;
alter table public.companies alter column payroll_payment_day set default 25,
 alter column payroll_payment_day set not null;
alter table public.companies add constraint company_payroll_payment_day_check check(payroll_payment_day between 1 and 31),
 add constraint company_payroll_month_offset_check check(payroll_payment_month_offset between 0 and 2),
 add constraint company_payroll_month_end_check check(payroll_closing_day=31),
 add constraint company_payroll_current_month_end_check check(payroll_payment_month_offset<>0 or payroll_payment_day=31);

create table public.payroll_confirmers(company_id uuid not null references public.companies(id) on delete cascade,
 position smallint not null check(position between 1 and 3),user_id uuid not null references auth.users(id) on delete cascade,
 primary key(company_id,position),unique(company_id,user_id));
insert into public.payroll_confirmers(company_id,position,user_id)
select company_id,1,user_id from (select cm.*,row_number() over(partition by company_id order by case when role::text='owner' then 0 else 1 end,user_id) as n from public.company_members cm where role::text in ('owner','admin'))x where n=1;
create table public.payroll_confirmation_history(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id) on delete cascade,
 statement_id uuid not null references public.payroll_statements(id) on delete cascade,reviewer_id uuid not null,
 revision integer not null,action text not null,created_at timestamptz not null default clock_timestamp());
create table public.payroll_confirmation_notices(company_id uuid not null references public.companies(id) on delete cascade,
 period_start date not null,recipient_user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('open','reminder')),notice_day date not null,
 primary key(company_id,period_start,recipient_user_id,kind,notice_day));
alter table public.payroll_confirmers enable row level security;
alter table public.payroll_confirmation_history enable row level security;
alter table public.payroll_confirmation_notices enable row level security;
revoke all on public.payroll_confirmers,public.payroll_confirmation_history,public.payroll_confirmation_notices from public,anon,authenticated;

create function private.payroll_confirmed_all(p_statement_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_confirmers c where c.company_id=ps.company_id)
 and not exists(select 1 from public.payroll_confirmers c where c.company_id=ps.company_id and not exists(
 select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision and r.confirmed_at is not null))
 from public.payroll_statements ps where ps.id=p_statement_id
$$;
create function private.payroll_payment_date(p_period_end date,p_company_id uuid,p_detail jsonb default '{}'::jsonb)
returns date language plpgsql stable security definer set search_path='' as $$
declare first_day date; day_number int; exact_date text;
begin
 exact_date:=coalesce(nullif(p_detail->>'payment_date',''),nullif(p_detail->>'支払年月日',''));
 if exact_date is not null and exact_date ~ '^\d{4}-\d{2}-\d{2}$' then return exact_date::date; end if;
 select (date_trunc('month',p_period_end)+make_interval(months=>c.payroll_payment_month_offset))::date,c.payroll_payment_day into first_day,day_number from public.companies c where id=p_company_id;
 if (p_detail->>'支払日') ~ '^([1-9]|[12][0-9]|3[01])$' then day_number:=(p_detail->>'支払日')::int; end if;
 return first_day+least(day_number,extract(day from first_day+interval '1 month - 1 day')::int)-1;
end $$;
create function public.payroll_company_policy() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() limit 1;
 if cid is null then raise exception 'company membership required'; end if;
 return (select jsonb_build_object('payment_day',payroll_payment_day,'payment_month_offset',payroll_payment_month_offset,'closing_day',payroll_closing_day,'can_manage_settings',exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=auth.uid() and cm.role::text in ('owner','admin'))) from public.companies where id=cid);
end $$;
create function public.set_payroll_company_policy(p_payment_day integer,p_payment_month_offset integer,p_closing_day integer default 31)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 if p_payment_day is null or p_payment_day not between 1 and 31 or p_payment_month_offset is null or p_payment_month_offset not between 0 and 2 or (p_payment_month_offset=0 and p_payment_day<>31) or p_closing_day is distinct from 31 then raise exception 'invalid payroll policy (month-end closing only)'; end if;
 update public.companies set payroll_payment_day=p_payment_day,payroll_payment_month_offset=p_payment_month_offset,payroll_closing_day=p_closing_day where id=cid;
end $$;
create function public.payroll_confirmation_candidates() returns table(user_id uuid,display_name text,role text,selected_position integer)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 return query select cm.user_id,coalesce(nullif(up.display_name,''),'SKOユーザー')::text,cm.role::text,pc.position::integer
 from public.company_members cm left join public.user_profiles up on up.user_id=cm.user_id left join public.payroll_confirmers pc on pc.company_id=cm.company_id and pc.user_id=cm.user_id
 where cm.company_id=cid and cm.role::text in ('owner','admin','manager','viewer') order by coalesce(pc.position,99),cm.user_id;
end $$;
create function public.set_payroll_confirmers(p_user_ids uuid[]) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; n int; u uuid; pos int:=0;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 n:=coalesce(array_length(p_user_ids,1),0);
 if n not between 1 and 3 or (select count(distinct x) from unnest(p_user_ids)x)<>n then raise exception 'select 1 to 3 unique confirmers'; end if;
 perform 1 from public.companies where id=cid for update;
 foreach u in array p_user_ids loop
 if not exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=u and cm.role::text in ('owner','admin','manager','viewer')) then raise exception 'invalid company confirmer'; end if;
 end loop;
 delete from public.payroll_confirmers where company_id=cid;
 foreach u in array p_user_ids loop pos:=pos+1; insert into public.payroll_confirmers values(cid,pos,u); end loop;
end $$;
create function private.payroll_confirmation_company() returns uuid language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select cm.company_id into cid from public.company_members cm join public.payroll_confirmers pc on pc.company_id=cm.company_id and pc.user_id=cm.user_id where cm.user_id=auth.uid() and cm.role::text in ('owner','admin','manager','viewer') limit 1;
 if cid is null then raise exception 'assigned payroll confirmer required'; end if;
 return cid;
end $$;
create or replace function private.set_payroll_review_check(p_statement_id uuid,p_revision integer,p_checked boolean)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.payroll_confirmation_company(); ps public.payroll_statements%rowtype; role_text text;
begin
 select * into ps from public.payroll_statements where id=p_statement_id and company_id=cid for update;
 if ps.id is null then raise exception 'payroll statement not found'; end if;
 if ps.revision is distinct from p_revision then raise exception 'payroll revision changed'; end if;
 if (current_timestamp at time zone 'Asia/Tokyo')::date<ps.period_end then raise exception 'confirmation opens at period end'; end if;
 select cm.role::text into role_text from public.company_members cm where cm.company_id=cid and cm.user_id=auth.uid();
 if role_text='manager' and not exists(select 1 from public.payroll_manager_worker_visibility v where v.company_id=cid and v.worker_id=ps.worker_id and v.visible_to_manager) then raise exception 'payroll visibility required'; end if;
 insert into public.payroll_statement_reviews(company_id,statement_id,reviewer_id,checked_revision,checked_at,updated_at)
 values(cid,ps.id,auth.uid(),case when p_checked then ps.revision end,case when p_checked then clock_timestamp() end,clock_timestamp())
 on conflict(statement_id,reviewer_id) do update set checked_revision=excluded.checked_revision,
 checked_at=case when public.payroll_statement_reviews.checked_revision=excluded.checked_revision then public.payroll_statement_reviews.checked_at else excluded.checked_at end,
 confirmed_revision=case when p_checked and public.payroll_statement_reviews.confirmed_revision=ps.revision then public.payroll_statement_reviews.confirmed_revision end,
 confirmed_at=case when p_checked and public.payroll_statement_reviews.confirmed_revision=ps.revision then public.payroll_statement_reviews.confirmed_at end,updated_at=clock_timestamp();
end $$;
create or replace function private.confirm_payroll_review_month(p_period_start date) returns integer language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.payroll_confirmation_company(); first_day date:=date_trunc('month',p_period_start)::date; n int; missing int; changed int;
begin
 if p_period_start is null then raise exception 'payroll month required'; end if;
 perform 1 from public.companies where id=cid for update;
 perform 1 from public.payroll_statements where company_id=cid and period_start=first_day order by id for update;
 select count(*),count(*) filter(where rv.checked_revision is distinct from ps.revision) into n,missing
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=auth.uid()
 where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee';
 if n=0 then raise exception 'no payroll statements'; end if;
 if (current_timestamp at time zone 'Asia/Tokyo')::date<(select max(period_end) from public.payroll_statements where company_id=cid and period_start=first_day) then raise exception 'confirmation opens at period end'; end if;
 if missing>0 then raise exception 'check all employee statements before confirmation'; end if;
 with changed_rows as(update public.payroll_statement_reviews rv set confirmed_revision=ps.revision,confirmed_at=clock_timestamp(),updated_at=clock_timestamp()
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
 where rv.statement_id=ps.id and rv.reviewer_id=auth.uid() and ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and rv.checked_revision=ps.revision and (rv.confirmed_revision is distinct from ps.revision or rv.confirmed_at is null)
 returning rv.statement_id,rv.confirmed_revision,rv.confirmed_at)
 insert into public.payroll_confirmation_history(company_id,statement_id,reviewer_id,revision,action,created_at)
 select cid,statement_id,auth.uid(),confirmed_revision,'confirmed',confirmed_at from changed_rows;
 get diagnostics changed=row_count; return changed;
end $$;
create or replace function private.finalize_payroll_review(p_period_start date) returns void language plpgsql security definer set search_path='' as $$
begin perform private.confirm_payroll_review_month(p_period_start); end $$;
create function public.cancel_payroll_review_month(p_period_start date) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.payroll_confirmation_company();
begin
 perform 1 from public.companies where id=cid for update;
 with changed_rows as(update public.payroll_statement_reviews rv set confirmed_revision=null,confirmed_at=null,updated_at=clock_timestamp() from public.payroll_statements ps
 where rv.statement_id=ps.id and rv.reviewer_id=auth.uid() and ps.company_id=cid and ps.period_start=date_trunc('month',p_period_start)::date and rv.confirmed_at is not null returning rv.statement_id,ps.revision)
 insert into public.payroll_confirmation_history(company_id,statement_id,reviewer_id,revision,action) select cid,statement_id,auth.uid(),revision,'cancelled' from changed_rows;
end $$;
create function public.payroll_confirmation_status(p_period_start date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; first_day date:=date_trunc('month',p_period_start)::date; open_day date; payday date; assigned boolean; all_confirmed boolean; own_confirmed boolean;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin','manager','viewer') limit 1;
 if cid is null then raise exception 'payroll review permission required'; end if;
 select max(period_end),min(private.payroll_payment_date(period_end,cid,case when workflow_state='draft' then '{}'::jsonb else detail end)) into open_day,payday from public.payroll_statements where company_id=cid and period_start=first_day;
 assigned:=exists(select 1 from public.payroll_confirmers where company_id=cid and user_id=auth.uid());
 all_confirmed:=open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not private.payroll_confirmed_all(ps.id));
 own_confirmed:=assigned and open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not exists(select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=auth.uid() and r.confirmed_revision=ps.revision and r.confirmed_at is not null));
 return jsonb_build_object('period_start',first_day,'confirmation_open_date',open_day,'payday',payday,'can_confirm',assigned and open_day is not null and (current_timestamp at time zone 'Asia/Tokyo')::date>=open_day and not own_confirmed,'can_cancel',own_confirmed,'reviewer_confirmed',own_confirmed,'confirmed',all_confirmed,
 'reviewers',coalesce((select jsonb_agg(jsonb_build_object('user_id',c.user_id,'name',coalesce(nullif(up.display_name,''),'SKOユーザー'),'position',c.position,
 'confirmed',open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not exists(select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision and r.confirmed_at is not null)),
 'confirmed_at',(select max(r.confirmed_at) from public.payroll_statement_reviews r join public.payroll_statements ps on ps.id=r.statement_id where ps.company_id=cid and ps.period_start=first_day and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision)) order by c.position)
 from public.payroll_confirmers c left join public.user_profiles up on up.user_id=c.user_id where c.company_id=cid),'[]'::jsonb));
end $$;
create function public.set_payroll_confirmation_settings(p_user_ids uuid[],p_payment_day integer,p_payment_month_offset integer,p_closing_day integer default 31)
returns void language plpgsql security definer set search_path='' as $$
begin perform public.set_payroll_company_policy(p_payment_day,p_payment_month_offset,p_closing_day); perform public.set_payroll_confirmers(p_user_ids); end $$;
create function private.enqueue_payroll_confirmation_notifications(p_today date default (current_timestamp at time zone 'Asia/Tokyo')::date,p_company_id uuid default null)
returns integer language plpgsql security definer set search_path='' as $$
declare r record; notice_kind text; notice_date date; changed int; total int:=0;
begin
 for r in select pc.company_id,pc.user_id,ps.period_start,max(ps.period_end) as opens,min(private.payroll_payment_date(ps.period_end,ps.company_id,case when ps.workflow_state='draft' then '{}'::jsonb else ps.detail end)) as payday,(array_agg(ps.id order by ps.id))[1] as statement_id
 from public.payroll_confirmers pc join public.company_members cm on cm.company_id=pc.company_id and cm.user_id=pc.user_id and cm.role::text in ('owner','admin','manager','viewer')
 join public.payroll_statements ps on ps.company_id=pc.company_id join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id and w.affiliation::text='employee'
 where (p_company_id is null or pc.company_id=p_company_id) and not exists(select 1 from public.payroll_statement_reviews rv where rv.statement_id=ps.id and rv.reviewer_id=pc.user_id and rv.confirmed_revision=ps.revision and rv.confirmed_at is not null)
 group by pc.company_id,pc.user_id,ps.period_start
 loop
 if p_today<r.opens or p_today>r.payday then continue; end if;
 for notice_kind,notice_date in select 'open'::text,r.opens union all select 'reminder',p_today where p_today between r.payday-7 and r.payday
 loop
 insert into public.payroll_confirmation_notices values(r.company_id,r.period_start,r.user_id,notice_kind,notice_date) on conflict do nothing;
 get diagnostics changed=row_count;
 if changed=1 then perform private.enqueue_notification(r.company_id,r.user_id,'approval',case when notice_kind='open' then '給与明細の確認' else '給与明細の確認が未完了です' end,'給料一覧で対象月の給与明細を確認してください。','payroll_review',r.statement_id); total:=total+1; end if;
 end loop;
 end loop;
 return total;
end $$;
create function public.enqueue_due_payroll_confirmation_notifications() returns integer language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() limit 1;
 if cid is null then raise exception 'company membership required'; end if;
 return private.enqueue_payroll_confirmation_notifications((current_timestamp at time zone 'Asia/Tokyo')::date,cid);
end $$;
-- pg_cron is installed in production; isolated databases can omit the extension.
do $$begin if exists(select 1 from pg_extension where extname='pg_cron') then
 execute 'select cron.schedule(''payroll-confirmation-daily-jst'',''0 15 * * *'',''select private.enqueue_payroll_confirmation_notifications();'')'; end if; end $$;

-- All new entry points require authenticated permission checks; internal dispatch is server-only.
revoke all on function private.payroll_confirmed_all(uuid),private.payroll_payment_date(date,uuid,jsonb),private.payroll_confirmation_company(),private.enqueue_payroll_confirmation_notifications(date,uuid) from public,anon,authenticated;
revoke all on function public.payroll_company_policy(),public.set_payroll_company_policy(integer,integer,integer),public.payroll_confirmation_candidates(),public.set_payroll_confirmers(uuid[]),public.payroll_confirmation_status(date),public.cancel_payroll_review_month(date),public.set_payroll_confirmation_settings(uuid[],integer,integer,integer),public.enqueue_due_payroll_confirmation_notifications() from public,anon;
grant execute on function public.payroll_company_policy(),public.set_payroll_company_policy(integer,integer,integer),public.payroll_confirmation_candidates(),public.set_payroll_confirmers(uuid[]),public.payroll_confirmation_status(date),public.cancel_payroll_review_month(date),public.set_payroll_confirmation_settings(uuid[],integer,integer,integer),public.enqueue_due_payroll_confirmation_notifications() to authenticated;

create or replace function private.payroll_review_workspace(p_period_start date default null)
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
  v_period_start date:=coalesce(
    p_period_start,
    date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date
  );
  result jsonb;
begin
  if not private.account_access_allowed() then raise exception 'ログインが必要です'; end if;

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
    'can_confirm',exists(select 1 from public.payroll_confirmers pc where pc.company_id=cid and pc.user_id=uid) and (current_timestamp at time zone 'Asia/Tokyo')::date >= (v_period_start+interval '1 month - 1 day')::date,
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
        'net_pay',ps.gross_pay+coalesce(adj.additions_yen,0)
          -ps.deductions-coalesce(adj.deductions_yen,0),
        'detail',coalesce(ps.detail,'{}'::jsonb)
          ||coalesce(adj.adjustment_detail,'{}'::jsonb),
        'revision',ps.revision,
        'workflow_state',ps.workflow_state,
        'review_checked',coalesce(rv.checked_revision=ps.revision,false),
        'review_confirmed',coalesce(private.payroll_confirmed_all(ps.id),false),
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


create or replace function private.my_payroll_review_statuses()
returns table(statement_id uuid,revision integer,review_confirmed boolean) language sql stable security definer set search_path='' as $$
 select ps.id,ps.revision,coalesce(private.payroll_confirmed_all(ps.id),false)
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
 where w.user_id=auth.uid() and private.account_access_allowed() order by ps.period_end desc
$$;
