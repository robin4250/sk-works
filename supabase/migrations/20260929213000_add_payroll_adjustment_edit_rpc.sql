create or replace function public.update_payroll_adjustment(
  p_id uuid,
  p_type_id uuid,
  p_amount_yen integer,
  p_effective_date date,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
$$;

revoke execute on function public.update_payroll_adjustment(
  uuid,uuid,integer,date,text
) from public, anon;

grant execute on function public.update_payroll_adjustment(
  uuid,uuid,integer,date,text
) to authenticated;
