-- Read-only installed source snapshot, 2026-10-09. Disposable fixture only.
-- No linked database execution. Actual functions; synthetic supporting permissions are separate.
CREATE OR REPLACE FUNCTION private.payroll_document_metadata(p_statement_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object(
 'company_seal_snapshot',ps.detail->'company_seal_snapshot',
 'company_seal_enabled',c.company_seal_enabled,
 'calculation_warnings',case when ps.workflow_state='draft' and ps.automatic_calculation then to_jsonb(private.payroll_condition_warnings(ps.company_id,ps.worker_id,ps.period_start,ps.period_end)) else '[]'::jsonb end,
 'pay_type',case
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('monthly','月給') then 'monthly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('hourly','時給') then 'hourly'
 when coalesce(nullif(ps.detail->>'pay_type',''),nullif(ps.detail->>'給与形態',''),nullif(ps.detail->>'給与方式','')) in ('daily','日給') then 'daily'
 else coalesce(pay_settings.pay_type,'daily') end,
 'rate_formula',coalesce(nullif(ps.detail->'rate_formula','null'::jsonb),pay_settings.rate_formula,'{}'::jsonb),
 'hourly_rate_yen',coalesce(nullif(ps.detail->'hourly_rate_yen','null'::jsonb),to_jsonb(pay_settings.hourly_rate_yen),'0'::jsonb),
 '社員番号',coalesce(nullif(ps.detail->>'社員番号',''),w.employee_number,''),
 '所属',coalesce(nullif(ps.detail->>'所属',''),w.department,''),
 '職種',coalesce(nullif(ps.detail->>'職種',''),w.role,''),
 '入社日',coalesce(nullif(ps.detail->>'入社日',''),w.hire_date::text,''),
 'payment_date',private.payroll_payment_date(ps.period_end,ps.company_id,case when ps.workflow_state='draft' then '{}'::jsonb else ps.detail end),
 '支払日',c.payroll_payment_day,
 'payroll_confirmations',coalesce((select jsonb_agg(jsonb_build_object('user_id',pc.user_id,'name',coalesce(nullif(up.display_name,''),'SKOユーザー'),'position',pc.position,
 'confirmed_at',case when rv.confirmed_revision=ps.revision then rv.confirmed_at end) order by pc.position)
 from public.payroll_confirmers pc left join public.user_profiles up on up.user_id=pc.user_id left join public.payroll_statement_reviews rv on rv.statement_id=ps.id and rv.reviewer_id=pc.user_id
 where pc.company_id=ps.company_id),'[]'::jsonb))
 from public.payroll_statements ps join public.workers w on w.id=ps.worker_id and w.company_id=ps.company_id join public.companies c on c.id=ps.company_id left join public.worker_payroll_settings pay_settings on pay_settings.worker_id=ps.worker_id and pay_settings.company_id=ps.company_id where ps.id=p_statement_id
$function$
;
CREATE OR REPLACE FUNCTION private.payroll_review_workspace(p_period_start date DEFAULT NULL::date)
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
$function$
;
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
  v_row public.payroll_adjustments%rowtype;
begin
  if coalesce((v_access ->> 'can_manage')::boolean, false) is not true then
    raise exception 'payroll adjustment manage permission required';
  end if;

  v_company_id := (v_access ->> 'company_id')::uuid;

  select *
  into v_row
  from public.payroll_adjustments
  where id = p_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'payroll adjustment not found';
  end if;

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
$function$
;
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
$function$
;
CREATE OR REPLACE FUNCTION public.my_payroll_statement_rows_with_adjustments()
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
  where w.user_id = v_user_id
  order by ps.period_end desc;
end;
$function$
;
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

  select *
  into v_before
  from public.payroll_adjustments
  where id = p_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'payroll adjustment not found';
  end if;

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
$function$
;
CREATE OR REPLACE FUNCTION private.guard_deletion_history_attribution()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare col text; before_value jsonb; after_value jsonb;
begin
 foreach col in array TG_ARGV loop
  after_value:=to_jsonb(new)->col;
  if TG_OP='UPDATE' then before_value:=to_jsonb(old)->col; else before_value:='null'::jsonb; end if;
  if after_value is distinct from before_value then
   if current_user not in ('postgres','service_role') or before_value<>'null'::jsonb
   then raise exception 'retained_attribution_immutable'; end if;
  end if;
 end loop;
 return new;
end $function$
;
CREATE TRIGGER deletion_history_attribution_guard BEFORE INSERT OR UPDATE ON public.payroll_statements FOR EACH ROW EXECUTE FUNCTION private.guard_deletion_history_attribution('retained_finalized_by');
CREATE OR REPLACE FUNCTION private.guard_blocked_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.workflow_state='finalized' and new.calculation_blocked then
  raise exception '出勤区分・手当・給与設定を確認してから確定してください。';
 end if;
 return new;
end;
$function$
;
CREATE TRIGGER guard_blocked_payroll BEFORE INSERT OR UPDATE ON public.payroll_statements FOR EACH ROW EXECUTE FUNCTION private.guard_blocked_payroll();
CREATE OR REPLACE FUNCTION private.preserve_document_company_seal_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous jsonb; incoming jsonb; preserved jsonb;
begin
 if tg_table_name='payroll_statements' then
  incoming:=coalesce(new.detail,'{}'::jsonb);
  if tg_op='UPDATE' then previous:=old.detail; end if;
 else
  incoming:=coalesce(new.snapshot,'{}'::jsonb);
  if tg_op='UPDATE' then previous:=old.snapshot; end if;
 end if;
 preserved:=private.document_company_seal_snapshot(previous,new.company_id,tg_op='INSERT');
 if tg_table_name='payroll_statements' then
  new.detail:=(incoming-'company_seal_snapshot')||preserved;
 else
  new.snapshot:=(incoming-'company_seal_snapshot')||preserved;
 end if;
 return new;
end $function$
;
CREATE TRIGGER zz_company_seal_snapshot BEFORE INSERT OR UPDATE ON public.payroll_statements FOR EACH ROW EXECUTE FUNCTION private.preserve_document_company_seal_snapshot();
