-- Staged only: atomic finalized payroll documents; no production application.
DO $$ BEGIN
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_document_metadata(uuid)') and md5(prosrc)='1ba003365a9154f6e66bcb04c884710e' and prosecdef and proconfig=array['search_path=""']) then raise exception 'final payroll prerequisite differs: private.payroll_document_metadata(uuid)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_review_workspace(date)') and md5(prosrc)='a2ab68566fd7fb79d0d22868f7172da8' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'final payroll prerequisite differs: private.payroll_review_workspace(date)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.cancel_payroll_adjustment(uuid,text)') and md5(prosrc)='9de32b373d59b766744742583c374e6e' and prosecdef and proconfig=ARRAY['search_path=public, pg_temp']) then raise exception 'final payroll prerequisite differs: cancel_payroll_adjustment(uuid,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.create_payroll_adjustment(uuid,uuid,integer,date,text)') and md5(prosrc)='7a78f48c4c87786d338586eeb2149771' and prosecdef and proconfig=ARRAY['search_path=public, pg_temp']) then raise exception 'final payroll prerequisite differs: create_payroll_adjustment(uuid,uuid,integer,date,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.my_payroll_statement_rows_with_adjustments()') and md5(prosrc)='2e86ab8cdf7adfbe8cb29399e5aedc37' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'final payroll prerequisite differs: my_payroll_statement_rows_with_adjustments()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.update_payroll_adjustment(uuid,uuid,integer,date,text)') and md5(prosrc)='ec6d2861b4777d99de20f21bd7270c14' and prosecdef and proconfig=ARRAY['search_path=public, pg_temp']) then raise exception 'final payroll prerequisite differs: update_payroll_adjustment(uuid,uuid,integer,date,text)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.apply_payroll_custom_money()') and md5(prosrc)='02807ef140cb91ae1f629ce5cd5f95db' and prosecdef and proconfig=array['search_path=""']) then raise exception 'final payroll resident prerequisite differs: private.apply_payroll_custom_money()'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.refresh_automatic_payroll_internal(uuid,uuid,date)') and md5(prosrc)='f845bd5071801a3502a6b195cf02b9f5' and prosecdef and proconfig=array['search_path=""']) then raise exception 'final payroll resident prerequisite differs: private.refresh_automatic_payroll_internal(uuid,uuid,date)'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.sync_payroll_attendance_detail(uuid,uuid,date)') and md5(prosrc)='cee56765d93e26bbed602339ced4c0d4' and prosecdef and proconfig=array['search_path=""']) then raise exception 'final payroll resident prerequisite differs: private.sync_payroll_attendance_detail(uuid,uuid,date)'; end if;
END $$;

create schema payroll_final_private;
revoke all on schema payroll_final_private from public,anon,authenticated;
create table payroll_final_private.documents(
 statement_id uuid primary key, company_id uuid not null,worker_id uuid not null,
 period_start date not null,period_end date not null, revision bigint not null,
 value jsonb not null,finalized_by uuid not null,finalized_at timestamptz not null,
 unique(company_id,worker_id,period_start,period_end)
);
create table payroll_final_private.history(
 id bigint generated always as identity primary key,statement_id uuid not null,
 company_id uuid not null,worker_id uuid not null,revision bigint not null,
 actor_id uuid not null,changed_at timestamptz not null,value jsonb not null
);
alter table payroll_final_private.documents enable row level security;
alter table payroll_final_private.history enable row level security;
revoke all on all tables in schema payroll_final_private from public,anon,authenticated;
revoke all on all sequences in schema payroll_final_private from public,anon,authenticated;

-- Internal scope helper: caller retains the original API's authorization checks.
create function payroll_final_private.lock_adjustment_scope(cid uuid,wid uuid,old_day date,new_day date)
returns void language plpgsql security definer set search_path='' as $$
declare m date;
begin
 perform 1 from public.companies where id=cid for key share;
 if not found then raise exception 'payroll company unavailable'; end if;
 perform 1 from public.workers where id=wid and company_id=cid for key share;
 if not found then raise exception 'payroll worker unavailable'; end if;
 for m in select distinct date_trunc('month',d)::date from unnest(array[old_day,new_day]) d where d is not null order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||m::text,0));
  if exists(select 1 from payroll_final_private.documents f where f.company_id=cid and f.worker_id=wid and m between f.period_start and f.period_end) then
   raise exception 'finalized payroll requires an explicit correction';
  end if;
 end loop;
end $$;
revoke all on function payroll_final_private.lock_adjustment_scope(uuid,uuid,date,date) from public,anon,authenticated;

create function payroll_final_private.finalize(p_statement_id uuid,p_expected_revision integer,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare initial public.payroll_statements%rowtype; ps public.payroll_statements%rowtype;
 saved payroll_final_private.documents%rowtype; settings jsonb; adjustments jsonb; adjustment_detail jsonb;
 additions bigint; removals bigint; doc jsonb; value jsonb; stamp timestamptz:=clock_timestamp();
 company_name text; worker_name text; bank jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
 if p_confirmed is not true then raise exception 'explicit finalization confirmation required'; end if;
 select * into initial from public.payroll_statements where id=p_statement_id;
 if not found or not coalesce(private.payroll_settings_allowed(initial.company_id,initial.worker_id,'edit'),false) then raise exception 'payroll access denied'; end if;
 perform 1 from public.companies where id=initial.company_id for update;
 if not found then raise exception 'payroll access denied'; end if;
 perform 1 from public.workers where id=initial.worker_id and company_id=initial.company_id for key share;
 if not found then raise exception 'payroll access denied'; end if;
 if initial.period_start is null or initial.period_end is null or initial.period_start<>date_trunc('month',initial.period_start)::date or initial.period_end<>(initial.period_start+interval '1 month - 1 day')::date then raise exception 'only canonical monthly payroll periods can be finalized'; end if;
 perform pg_advisory_xact_lock(hashtextextended(initial.company_id::text||initial.worker_id::text||initial.period_start::text,0));
 select * into ps from public.payroll_statements where id=p_statement_id for update;
 if not found or (ps.company_id,ps.worker_id,ps.period_start,ps.period_end) is distinct from (initial.company_id,initial.worker_id,initial.period_start,initial.period_end) then raise exception 'payroll scope changed'; end if;
 select * into saved from payroll_final_private.documents where statement_id=ps.id;
 if found then
  if ps.workflow_state<>'finalized' or saved.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
  return jsonb_build_object('finalized',true,'revision',saved.revision,'snapshot',jsonb_set(saved.value,'{detail,bank_account}','{}'::jsonb));
 end if;
 if not ps.automatic_calculation or ps.workflow_state<>'draft' then raise exception 'only automatic draft can be finalized; legacy finalization is not backfilled'; end if;
 if p_expected_revision is null or ps.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
 perform private.refresh_automatic_payroll_internal(ps.company_id,ps.worker_id,ps.period_start);
 perform private.sync_payroll_attendance_detail(ps.company_id,ps.worker_id,ps.period_start);
 select * into ps from public.payroll_statements where id=p_statement_id;
 if ps.revision is distinct from p_expected_revision then return jsonb_build_object('finalized',false,'reason','recalculation_changed','revision',ps.revision); end if;
 if ps.calculation_blocked then raise exception 'payroll calculation blocked'; end if;
 if not coalesce(private.payroll_confirmed_all(ps.id),false) or exists(
  select 1 from public.payroll_confirmers c left join public.payroll_statement_reviews r on r.statement_id=ps.id and r.reviewer_id=c.user_id
  where c.company_id=ps.company_id and (r.checked_revision is distinct from ps.revision or r.confirmed_revision is distinct from ps.revision or r.confirmed_at is null)
 ) then raise exception 'all current revision reviews required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'label',a.label_snapshot,'direction',a.direction,'amount_yen',a.amount_yen,'effective_date',a.effective_date) order by a.effective_date,a.id),'[]'),
 coalesce(sum(a.amount_yen) filter(where a.direction='addition'),0),coalesce(sum(a.amount_yen) filter(where a.direction='deduction'),0)
 into adjustments,additions,removals from public.payroll_adjustments a where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null;
 select coalesce(jsonb_object_agg(label,total),'{}') into adjustment_detail from (
  select a.label_snapshot label,sum(case when a.direction='addition' then a.amount_yen else -a.amount_yen end)::integer total from public.payroll_adjustments a
  where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null group by a.label_snapshot
 ) grouped;
 select c.name,w.name into company_name,worker_name from public.companies c join public.workers w on w.company_id=c.id where c.id=ps.company_id and w.id=ps.worker_id;
 select coalesce(to_jsonb(s)-array['company_id','worker_id','created_by','updated_by','created_at','updated_at'],'{}') into settings from public.worker_payroll_settings s where s.company_id=ps.company_id and s.worker_id=ps.worker_id;
 select jsonb_build_object('bank_name',b.bank_name,'branch_name',b.branch_name,'account_type',b.account_type,'account_number',b.account_number,'account_holder',b.account_holder) into bank from public.worker_private_bank_accounts b where b.company_id=ps.company_id and b.worker_id=ps.worker_id order by b.updated_at desc nulls last limit 1;
 doc:=private.payroll_document_metadata(ps.id);
 value:=jsonb_build_object('schema_version',1,'calculator_version','resident-tax-20261009161427','statement_id',ps.id,'revision',ps.revision,
 'period_start',ps.period_start,'period_end',ps.period_end,'issued_at',ps.issued_at,'company_name',company_name,'worker_name',worker_name,
 'base_result',jsonb_build_object('gross_pay',ps.gross_pay,'deductions',ps.deductions,'net_pay',ps.net_pay),
 'result',jsonb_build_object('gross_pay',(ps.gross_pay+additions)::integer,'deductions',(ps.deductions+removals)::integer,'net_pay',(ps.gross_pay+additions-ps.deductions-removals)::integer),
 'conditions',jsonb_build_object('settings',coalesce(settings,'{}'),'resident_tax',resident_tax_private.resolve(ps.company_id,ps.worker_id,ps.period_start),'family_allowance_mode','legacy_fixed','company_rate_registry_adopted',false,'income_tax_table_registry_adopted',false),
 'adjustments',adjustments,'document_metadata',doc,'detail',coalesce(ps.detail,'{}')||adjustment_detail||jsonb_build_object('bank_account',coalesce(bank,'{}'))||doc,
 'finalized_by',auth.uid(),'finalized_at',stamp);
 insert into payroll_final_private.documents values(ps.id,ps.company_id,ps.worker_id,ps.period_start,ps.period_end,ps.revision,value,auth.uid(),stamp);
 update public.payroll_statements set workflow_state='finalized',finalized_by=auth.uid(),finalized_at=stamp where id=ps.id;
 insert into payroll_final_private.history(statement_id,company_id,worker_id,revision,actor_id,changed_at,value) values(ps.id,ps.company_id,ps.worker_id,ps.revision,auth.uid(),stamp,value);
 return jsonb_build_object('finalized',true,'revision',ps.revision,'snapshot',jsonb_set(value,'{detail,bank_account}','{}'::jsonb));
end $$;
revoke all on function payroll_final_private.finalize(uuid,integer,boolean) from public,anon;
grant usage on schema payroll_final_private to authenticated;
grant execute on function payroll_final_private.finalize(uuid,integer,boolean) to authenticated;
create function public.finalize_payroll_statement(p_statement_id uuid,p_expected_revision integer,p_confirmed boolean)
returns jsonb language sql security invoker set search_path='' as $$ select payroll_final_private.finalize(p_statement_id,p_expected_revision,p_confirmed) $$;
revoke all on function public.finalize_payroll_statement(uuid,integer,boolean) from public,anon;
grant execute on function public.finalize_payroll_statement(uuid,integer,boolean) to authenticated;

-- Preserve reviewed draft behavior as internal helpers, avoiding source-string mutation.
alter function private.payroll_document_metadata(uuid) rename to payroll_live_document_metadata;
create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select case when ps.workflow_state='draft' then private.payroll_live_document_metadata(ps.id)
 else coalesce(f.value->'document_metadata','{}'::jsonb) end
 from public.payroll_statements ps left join payroll_final_private.documents f on f.statement_id=ps.id where ps.id=p_statement_id
$$;
revoke all on function private.payroll_document_metadata(uuid) from public,anon,authenticated;

alter function public.my_payroll_statement_rows_with_adjustments() set schema payroll_final_private;
alter function payroll_final_private.my_payroll_statement_rows_with_adjustments() rename to live_my_rows;
CREATE OR REPLACE FUNCTION payroll_final_private.live_my_rows()
 RETURNS TABLE(id uuid, period_start date, period_end date, gross_pay integer, deductions integer, net_pay integer, detail jsonb, issued_at timestamp with time zone, company_name text, worker_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  return query
  select
    ps.id,
    ps.period_start,
    ps.period_end,
    ps.gross_pay + coalesce(adj.additions_yen, 0),
    ps.deductions + coalesce(adj.deductions_yen, 0),
    (
      ps.gross_pay
      + coalesce(adj.additions_yen, 0)
      - ps.deductions
      - coalesce(adj.deductions_yen, 0)
    )::integer,
    coalesce(ps.detail, '{}'::jsonb)
      || jsonb_build_object(
        'pay_type',case
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('monthly','月給') then 'monthly'
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('hourly','時給') then 'hourly'
          when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('daily','日給') then 'daily'
          else coalesce(pay_settings.pay_type,'daily') end,
        'rate_formula',coalesce(nullif(ps.detail->'rate_formula','null'::jsonb),pay_settings.rate_formula,'{}'::jsonb),
        'hourly_rate_yen',coalesce(nullif(ps.detail->'hourly_rate_yen','null'::jsonb),to_jsonb(pay_settings.hourly_rate_yen),'0'::jsonb)
      )
      || coalesce(adj.adjustment_detail, '{}'::jsonb)
      || jsonb_build_object('bank_account',coalesce(bank.bank_detail,'{}'::jsonb))
      || private.payroll_document_metadata(ps.id),
    ps.issued_at,
    c.name,
    w.name
  from public.payroll_statements ps
  join public.workers w
    on w.id = ps.worker_id
   and w.company_id = ps.company_id
  join public.companies c
    on c.id = ps.company_id
  left join public.worker_payroll_settings pay_settings
    on pay_settings.worker_id=ps.worker_id and pay_settings.company_id=ps.company_id
  left join lateral (
    with active as (
      select
        a.label_snapshot,
        a.direction,
        a.amount_yen
      from public.payroll_adjustments a
      where a.company_id = ps.company_id
        and a.worker_id = ps.worker_id
        and a.effective_date between ps.period_start and ps.period_end
        and a.cancelled_at is null
    ),
    totals as (
      select
        coalesce(
          sum(case when direction = 'addition' then amount_yen else 0 end),
          0
        )::integer as additions_yen,
        coalesce(
          sum(case when direction = 'deduction' then amount_yen else 0 end),
          0
        )::integer as deductions_yen
      from active
    ),
    grouped as (
      select
        label_snapshot,
        sum(
          case
            when direction = 'addition' then amount_yen
            else -amount_yen
          end
        )::integer as signed_total
      from active
      group by label_snapshot
    )
    select
      t.additions_yen,
      t.deductions_yen,
      coalesce(
        (
          select jsonb_object_agg(g.label_snapshot, g.signed_total)
          from grouped g
        ),
        '{}'::jsonb
      ) as adjustment_detail
    from totals t
  ) adj on true
  left join lateral (
    select jsonb_build_object(
      'bank_name',b.bank_name,'branch_name',b.branch_name,
      'account_type',b.account_type,'account_number',b.account_number,
      'account_holder',b.account_holder
    ) as bank_detail
    from public.worker_private_bank_accounts b
    where b.worker_id=ps.worker_id and b.company_id=ps.company_id
      and private.account_access_allowed()
    order by b.updated_at desc nulls last
    limit 1
  ) bank on true
  where ps.workflow_state='draft' and w.user_id = v_user_id
  order by ps.period_end desc;
end;
$function$
;
revoke all on function payroll_final_private.live_my_rows() from public,anon,authenticated;
create function public.my_payroll_statement_rows_with_adjustments()
returns table(id uuid,period_start date,period_end date,gross_pay integer,deductions integer,net_pay integer,detail jsonb,issued_at timestamptz,company_name text,worker_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'authentication required'; end if;
 return query
 select r.id,r.period_start,r.period_end,r.gross_pay,r.deductions,r.net_pay,r.detail,r.issued_at,r.company_name,r.worker_name
 from payroll_final_private.live_my_rows() r
 union all
 select ps.id,ps.period_start,ps.period_end,
 coalesce((f.value#>>'{result,gross_pay}')::integer,ps.gross_pay),
 coalesce((f.value#>>'{result,deductions}')::integer,ps.deductions),
 coalesce((f.value#>>'{result,net_pay}')::integer,ps.net_pay),
 coalesce(f.value->'detail',ps.detail,'{}'),ps.issued_at,
 coalesce(f.value->>'company_name',ps.detail->>'company_name',''),
 coalesce(f.value->>'worker_name',ps.detail->>'worker_name','')
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
 join public.companies c on c.id=ps.company_id
 left join payroll_final_private.documents f on f.statement_id=ps.id
 where ps.workflow_state<>'draft' and w.user_id=auth.uid()
 order by period_end desc;
end $$;
revoke all on function public.my_payroll_statement_rows_with_adjustments() from public,anon;
grant execute on function public.my_payroll_statement_rows_with_adjustments() to authenticated;

alter function private.payroll_review_workspace(date) rename to payroll_live_review_workspace;
CREATE OR REPLACE FUNCTION private.payroll_live_review_workspace(p_period_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      where ps.workflow_state='draft' and ps.company_id=cid
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
$function$
;
revoke all on function private.payroll_live_review_workspace(date) from public,anon,authenticated;
create function private.payroll_review_workspace(p_period_start date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare workspace jsonb;items jsonb;cid uuid;role_text text;
begin
 workspace:=private.payroll_live_review_workspace(p_period_start);
 select cm.company_id,cm.role::text into cid,role_text from public.company_members cm where cm.user_id=auth.uid() limit 1;
 select coalesce(jsonb_agg(item order by worker_sort,id),'[]') into items from (
  select r.value item,r.value->>'worker_name' worker_sort,(r.value->>'id')::uuid id
  from jsonb_array_elements(workspace->'statements') r(value)
  union all
  select jsonb_build_object('id',ps.id,'worker_id',ps.worker_id,
   'worker_name',coalesce(f.value->>'worker_name',ps.detail->>'worker_name',''),
   'company_name',coalesce(f.value->>'company_name',ps.detail->>'company_name',''),
   'period_start',ps.period_start,'period_end',ps.period_end,
   'gross_pay',coalesce((f.value#>>'{result,gross_pay}')::integer,ps.gross_pay),
   'deductions',coalesce((f.value#>>'{result,deductions}')::integer,ps.deductions),
   'net_pay',coalesce((f.value#>>'{result,net_pay}')::integer,ps.net_pay),
   'detail',jsonb_set(coalesce(f.value->'detail',ps.detail,'{}'),'{bank_account}','{}'::jsonb),
   'revision',ps.revision,'workflow_state',ps.workflow_state,
   'review_checked',coalesce(rv.checked_revision=ps.revision,false),
   'review_confirmed',coalesce(private.payroll_confirmed_all(ps.id),false),
   'reviewer_confirmed',coalesce(rv.confirmed_revision=ps.revision,false)),
   w.name,ps.id
  from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id
  join public.companies c on c.id=ps.company_id
  left join public.payroll_manager_worker_visibility v on v.company_id=ps.company_id and v.worker_id=ps.worker_id
  left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=auth.uid()
  left join payroll_final_private.documents f on f.statement_id=ps.id
  where ps.company_id=cid and ps.period_start=(workspace->>'period_start')::date
   and ps.workflow_state<>'draft' and w.affiliation::text='employee'
   and (role_text in ('owner','admin','viewer') or (role_text='manager' and coalesce(v.visible_to_manager,false)))
 ) rows;
 return workspace||jsonb_build_object('statements',items);
end $$;
revoke all on function private.payroll_review_workspace(date) from public,anon,authenticated;

-- Full reviewed adjustment definitions; only scope sequencing is changed.
CREATE OR REPLACE FUNCTION public.create_payroll_adjustment(p_worker_id uuid, p_type_id uuid, p_amount_yen integer, p_effective_date date, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_label text;
  v_direction text;
  v_id uuid;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  if p_amount_yen is null or p_amount_yen <= 0 then
    raise exception 'amount must be greater than zero';
  end if;

  if p_effective_date is null then
    raise exception 'effective date is required';
  end if;

  if not exists (
    select 1
    from public.workers w
    where w.id = p_worker_id
      and w.company_id = v_company_id
      and w.status = 'active'
  ) then
    raise exception 'worker not found';
  end if;

  select t.label, t.direction
  into v_label, v_direction
  from public.payroll_adjustment_types t
  where t.id = p_type_id
    and t.company_id = v_company_id
    and t.is_active = true;

  if v_label is null then
    raise exception 'active payroll adjustment type not found';
  end if;

  if not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
  perform payroll_final_private.lock_adjustment_scope(v_company_id,p_worker_id,null,p_effective_date);

  insert into public.payroll_adjustments(
    company_id,
    worker_id,
    type_id,
    label_snapshot,
    direction,
    amount_yen,
    effective_date,
    note,
    created_by
  )
  values(
    v_company_id,
    p_worker_id,
    p_type_id,
    v_label,
    v_direction,
    p_amount_yen,
    p_effective_date,
    nullif(trim(coalesce(p_note, '')), ''),
    v_actor
  )
  returning id into v_id;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'adjustment_create',
    'adjustment',
    v_id,
    v_actor,
    jsonb_build_object(
      'worker_id', p_worker_id,
      'type_id', p_type_id,
      'label', v_label,
      'direction', v_direction,
      'amount_yen', p_amount_yen,
      'effective_date', p_effective_date
    )
  );

  return v_id;
end;
$function$;

revoke all on function public.create_payroll_adjustment(uuid,uuid,integer,date,text) from public,anon;
CREATE OR REPLACE FUNCTION public.update_payroll_adjustment(p_id uuid, p_type_id uuid, p_amount_yen integer, p_effective_date date, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_scope public.payroll_adjustments%rowtype;
  v_before public.payroll_adjustments%rowtype;
  v_label text;
  v_direction text;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  if p_amount_yen is null or p_amount_yen <= 0 then
    raise exception 'amount must be greater than zero';
  end if;

  if p_effective_date is null then
    raise exception 'effective date is required';
  end if;

  if not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
  select * into v_scope from public.payroll_adjustments where id=p_id and company_id=v_company_id;
  if not found then raise exception 'payroll adjustment not found'; end if;
  perform payroll_final_private.lock_adjustment_scope(v_company_id,v_scope.worker_id,v_scope.effective_date,p_effective_date);

  select *
  into v_before
  from public.payroll_adjustments
  where id = p_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'payroll adjustment not found';
  end if;
  if (v_before.worker_id,v_before.effective_date) is distinct from (v_scope.worker_id,v_scope.effective_date) then raise exception 'payroll adjustment scope changed' using errcode='40001'; end if;

  if v_before.cancelled_at is not null then
    raise exception 'cancelled payroll adjustment cannot be edited';
  end if;

  select t.label, t.direction
  into v_label, v_direction
  from public.payroll_adjustment_types t
  where t.id = p_type_id
    and t.company_id = v_company_id
    and t.is_active = true;

  if v_label is null then
    raise exception 'active payroll adjustment type not found';
  end if;

  update public.payroll_adjustments
  set type_id = p_type_id,
      label_snapshot = v_label,
      direction = v_direction,
      amount_yen = p_amount_yen,
      effective_date = p_effective_date,
      note = nullif(trim(coalesce(p_note, '')), ''),
      updated_at = now()
  where id = p_id
    and company_id = v_company_id;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'adjustment_update',
    'adjustment',
    p_id,
    v_actor,
    jsonb_build_object(
      'before', jsonb_build_object(
        'type_id', v_before.type_id,
        'label', v_before.label_snapshot,
        'direction', v_before.direction,
        'amount_yen', v_before.amount_yen,
        'effective_date', v_before.effective_date,
        'note', v_before.note
      ),
      'after', jsonb_build_object(
        'type_id', p_type_id,
        'label', v_label,
        'direction', v_direction,
        'amount_yen', p_amount_yen,
        'effective_date', p_effective_date,
        'note', nullif(trim(coalesce(p_note, '')), '')
      )
    )
  );
end;
$function$;

revoke all on function public.update_payroll_adjustment(uuid,uuid,integer,date,text) from public,anon;
CREATE OR REPLACE FUNCTION public.cancel_payroll_adjustment(p_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_access jsonb := public.payroll_adjustment_access();
  v_company_id uuid;
  v_scope public.payroll_adjustments%rowtype;
  v_row public.payroll_adjustments%rowtype;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  if not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
  select * into v_scope from public.payroll_adjustments where id=p_id and company_id=v_company_id;
  if not found then raise exception 'payroll adjustment not found'; end if;
  perform payroll_final_private.lock_adjustment_scope(v_company_id,v_scope.worker_id,v_scope.effective_date,v_scope.effective_date);

  select *
  into v_row
  from public.payroll_adjustments
  where id = p_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'payroll adjustment not found';
  end if;
  if (v_row.worker_id,v_row.effective_date) is distinct from (v_scope.worker_id,v_scope.effective_date) then raise exception 'payroll adjustment scope changed' using errcode='40001'; end if;

  if v_row.cancelled_at is not null then
    return;
  end if;

  update public.payroll_adjustments
  set cancelled_at = now(),
      cancelled_by = v_actor,
      cancellation_reason =
        nullif(trim(coalesce(p_reason, '')), ''),
      updated_at = now()
  where id = p_id
    and company_id = v_company_id;

  insert into public.payroll_adjustment_audit_log(
    company_id,
    action,
    target_kind,
    target_id,
    actor_user_id,
    details
  )
  values(
    v_company_id,
    'adjustment_cancel',
    'adjustment',
    p_id,
    v_actor,
    jsonb_build_object(
      'worker_id', v_row.worker_id,
      'label', v_row.label_snapshot,
      'direction', v_row.direction,
      'amount_yen', v_row.amount_yen,
      'effective_date', v_row.effective_date,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );
end;
$function$;

revoke all on function public.cancel_payroll_adjustment(uuid,text) from public,anon;

create function payroll_final_private.adjustment_scope_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare scopes jsonb:='[]'; r record;
begin
 if tg_op<>'INSERT' then scopes:=scopes||jsonb_build_array(jsonb_build_object('cid',old.company_id,'wid',old.worker_id,'month',date_trunc('month',old.effective_date)::date)); end if;
 if tg_op<>'DELETE' then scopes:=scopes||jsonb_build_array(jsonb_build_object('cid',new.company_id,'wid',new.worker_id,'month',date_trunc('month',new.effective_date)::date)); end if;
 for r in select distinct (v->>'cid')::uuid cid,(v->>'wid')::uuid wid,(v->>'month')::date scope_month from jsonb_array_elements(scopes) v order by cid,wid,scope_month loop
  -- Company cascading deletion may remove active data, while documents remain logical history.
  if exists(select 1 from public.companies c join public.workers w on w.company_id=c.id where c.id=r.cid and w.id=r.wid) then
   perform pg_advisory_xact_lock(hashtextextended(r.cid::text||r.wid::text||r.scope_month::text,0));
   if exists(select 1 from payroll_final_private.documents f where f.company_id=r.cid and f.worker_id=r.wid and r.scope_month between f.period_start and f.period_end) then raise exception 'finalized payroll requires an explicit correction'; end if;
  end if;
 end loop;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
create trigger payroll_final_adjustment_scope before insert or update or delete on public.payroll_adjustments for each row execute function payroll_final_private.adjustment_scope_guard();

create function payroll_final_private.adjustment_revision_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare before_value jsonb;after_value jsonb;scopes jsonb:='[]';r record;
begin
 if tg_op<>'INSERT' and old.cancelled_at is null then
  before_value:=jsonb_build_object('cid',old.company_id,'wid',old.worker_id,'id',old.id,'label',old.label_snapshot,'direction',old.direction,'amount',old.amount_yen,'date',old.effective_date);
 end if;
 if tg_op<>'DELETE' and new.cancelled_at is null then
  after_value:=jsonb_build_object('cid',new.company_id,'wid',new.worker_id,'id',new.id,'label',new.label_snapshot,'direction',new.direction,'amount',new.amount_yen,'date',new.effective_date);
 end if;
 if before_value is not distinct from after_value then return null; end if;
 if before_value is not null then scopes:=scopes||jsonb_build_array(before_value); end if;
 if after_value is not null then scopes:=scopes||jsonb_build_array(after_value); end if;
 for r in select distinct (v->>'cid')::uuid cid,(v->>'wid')::uuid wid,date_trunc('month',(v->>'date')::date)::date scope_month from jsonb_array_elements(scopes) v order by cid,wid,scope_month loop
  update public.payroll_statements set revision=revision+1,approved_ids='{}'::uuid[],updated_at=clock_timestamp()
  where company_id=r.cid and worker_id=r.wid and period_start=r.scope_month and automatic_calculation and workflow_state='draft';
 end loop;
 return null;
end $$;
create trigger payroll_final_adjustment_revision after insert or update or delete on public.payroll_adjustments for each row execute function payroll_final_private.adjustment_revision_changed();
revoke all on function payroll_final_private.adjustment_scope_guard() from public,anon,authenticated;
revoke all on function payroll_final_private.adjustment_revision_changed() from public,anon,authenticated;

-- Read-only UI capability; never recalculates or registers a review.
create function payroll_final_private.read_status(p_statement_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare ps public.payroll_statements%rowtype; allowed boolean; ready boolean; saved boolean;
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true then raise exception 'payroll access denied' using errcode='42501';end if;
 select * into ps from public.payroll_statements where id=p_statement_id;
 if not found or not exists(select 1 from public.companies c join public.workers w on w.company_id=c.id where c.id=ps.company_id and w.id=ps.worker_id)
 or not coalesce(private.payroll_settings_allowed(ps.company_id,ps.worker_id,'view'),false) then raise exception 'payroll access denied' using errcode='42501';end if;
 allowed:=coalesce(private.payroll_settings_allowed(ps.company_id,ps.worker_id,'edit'),false);
 saved:=exists(select 1 from payroll_final_private.documents d where d.statement_id=ps.id);
 ready:=coalesce(private.payroll_confirmed_all(ps.id),false) and not exists(
 select 1 from public.payroll_confirmers c left join public.payroll_statement_reviews r on r.statement_id=ps.id and r.reviewer_id=c.user_id
 where c.company_id=ps.company_id and (r.checked_revision is distinct from ps.revision or r.confirmed_revision is distinct from ps.revision or r.confirmed_at is null));
 return jsonb_build_object('contract_version',1,'statement_id',ps.id,'revision',ps.revision,
 'period_start',ps.period_start,'period_end',ps.period_end,'workflow_state',ps.workflow_state,
 'snapshot_saved',saved,'can_finalize',allowed and ps.automatic_calculation and ps.workflow_state='draft'
 and ps.period_start=date_trunc('month',ps.period_start)::date and ps.period_end=(ps.period_start+interval '1 month - 1 day')::date
 and not coalesce(ps.calculation_blocked,true) and ready);
end$$;
revoke all on function payroll_final_private.read_status(uuid) from public,anon;
grant execute on function payroll_final_private.read_status(uuid) to authenticated;
create function public.read_payroll_finalization_status(p_statement_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$select payroll_final_private.read_status(p_statement_id)$$;
revoke all on function public.read_payroll_finalization_status(uuid) from public,anon;
grant execute on function public.read_payroll_finalization_status(uuid) to authenticated;
