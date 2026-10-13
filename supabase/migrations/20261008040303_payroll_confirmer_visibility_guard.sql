-- Confirmation assignments never grant payroll visibility.
create or replace function private.payroll_confirmer_eligible(p_company_id uuid,p_user_id uuid,p_period_start date default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.company_members cm
 where cm.company_id=p_company_id and cm.user_id=p_user_id
 and (cm.role::text in ('owner','admin','viewer') or
 (cm.role::text='manager' and not exists(
 select 1 from public.workers w where w.company_id=p_company_id and w.affiliation::text='employee'
 and (p_period_start is null or exists(select 1 from public.payroll_statements ps where ps.company_id=w.company_id and ps.worker_id=w.id and ps.period_start=date_trunc('month',p_period_start)::date))
 and not exists(select 1 from public.payroll_manager_worker_visibility v where v.company_id=w.company_id and v.worker_id=w.id and v.visible_to_manager)))))
$$;
revoke all on function private.payroll_confirmer_eligible(uuid,uuid,date) from public,anon,authenticated;

create or replace function public.payroll_confirmation_candidates() returns table(user_id uuid,display_name text,role text,selected_position integer)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select member.company_id into cid from public.company_members member where member.user_id=auth.uid() and member.role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 return query select cm.user_id,coalesce(nullif(up.display_name,''),'SKOユーザー')::text,cm.role::text,pc.position::integer
 from public.company_members cm left join public.user_profiles up on up.user_id=cm.user_id left join public.payroll_confirmers pc on pc.company_id=cm.company_id and pc.user_id=cm.user_id
 where cm.company_id=cid and cm.role::text in ('owner','admin','manager','viewer')
 and (pc.user_id is not null or private.payroll_confirmer_eligible(cid,cm.user_id,null)) order by coalesce(pc.position,99),cm.user_id;
end $$;

create or replace function public.set_payroll_confirmers(p_user_ids uuid[]) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; n int; u uuid; pos int:=0;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select member.company_id into cid from public.company_members member where member.user_id=auth.uid() and member.role::text in ('owner','admin') limit 1;
 if cid is null then raise exception 'company administrator required'; end if;
 n:=coalesce(array_length(p_user_ids,1),0);
 if n not between 1 and 3 or (select count(distinct x) from unnest(p_user_ids)x)<>n then raise exception 'select 1 to 3 unique confirmers'; end if;
 perform 1 from public.companies where id=cid for update;
 foreach u in array p_user_ids loop
 if not exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=u and cm.role::text in ('owner','admin','manager','viewer')) then raise exception 'invalid company confirmer'; end if;
 if not private.payroll_confirmer_eligible(cid,u,null) then raise exception 'サブ管理者を確認者にするには、全社員の給与閲覧権限が必要です。'; end if;
 end loop;
 delete from public.payroll_confirmers where company_id=cid;
 foreach u in array p_user_ids loop pos:=pos+1; insert into public.payroll_confirmers values(cid,pos,u); end loop;
end $$;

create or replace function public.payroll_confirmation_status(p_period_start date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; first_day date:=date_trunc('month',p_period_start)::date; open_day date; payday date; assigned boolean; all_confirmed boolean; own_confirmed boolean;
begin
 if not private.account_access_allowed() then raise exception 'authentication required'; end if;
 select company_id into cid from public.company_members where user_id=auth.uid() and role::text in ('owner','admin','manager','viewer') limit 1;
 if cid is null then raise exception 'payroll review permission required'; end if;
 select max(period_end),min(private.payroll_payment_date(period_end,cid,case when workflow_state='draft' then '{}'::jsonb else detail end)) into open_day,payday from public.payroll_statements where company_id=cid and period_start=first_day;
 assigned:=exists(select 1 from public.payroll_confirmers where company_id=cid and user_id=auth.uid());
 all_confirmed:=open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not private.payroll_confirmed_all(ps.id));
 own_confirmed:=assigned and open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not exists(select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=auth.uid() and r.confirmed_revision=ps.revision and r.confirmed_at is not null));
 return jsonb_build_object('period_start',first_day,'confirmation_open_date',open_day,'payday',payday,'can_confirm',assigned and private.payroll_confirmer_eligible(cid,auth.uid(),first_day) and open_day is not null and (current_timestamp at time zone 'Asia/Tokyo')::date>=open_day and not own_confirmed,'can_cancel',own_confirmed,'reviewer_confirmed',own_confirmed,'confirmed',all_confirmed,
 'reviewers',coalesce((select jsonb_agg(jsonb_build_object('user_id',c.user_id,'name',coalesce(nullif(up.display_name,''),'SKOユーザー'),'position',c.position,
 'confirmed',open_day is not null and not exists(select 1 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id where ps.company_id=cid and ps.period_start=first_day and w.affiliation::text='employee' and not exists(select 1 from public.payroll_statement_reviews r where r.statement_id=ps.id and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision and r.confirmed_at is not null)),
 'confirmed_at',(select max(r.confirmed_at) from public.payroll_statement_reviews r join public.payroll_statements ps on ps.id=r.statement_id where ps.company_id=cid and ps.period_start=first_day and r.reviewer_id=c.user_id and r.confirmed_revision=ps.revision)) order by c.position)
 from public.payroll_confirmers c left join public.user_profiles up on up.user_id=c.user_id where c.company_id=cid),'[]'::jsonb));
end $$;

create or replace function private.confirm_payroll_review_month(p_period_start date) returns integer language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.payroll_confirmation_company(); first_day date:=date_trunc('month',p_period_start)::date; n int; missing int; changed int;
begin
 if p_period_start is null then raise exception 'payroll month required'; end if;
 if not private.payroll_confirmer_eligible(cid,auth.uid(),first_day) then raise exception 'payroll visibility required'; end if;
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
    'can_confirm',private.payroll_confirmer_eligible(cid,uid,v_period_start) and exists(select 1 from public.payroll_confirmers pc where pc.company_id=cid and pc.user_id=uid) and (current_timestamp at time zone 'Asia/Tokyo')::date >= (v_period_start+interval '1 month - 1 day')::date,
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
          ||coalesce(adj.adjustment_detail,'{}'::jsonb)||private.payroll_document_metadata(ps.id),
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
