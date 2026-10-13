-- One company-wide switch for the generated seal on every financial document.
-- Actual selectable typefaces remain unavailable until licensed assets are supplied.
alter table public.companies
  add column if not exists company_seal_enabled boolean not null default true;

-- Existing company SELECT grants enumerate columns; this nonfinancial flag
-- remains scoped by the existing membership RLS. No write privilege is added.
grant select(company_seal_enabled) on public.companies to authenticated;

create function public.company_seal_settings()
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  member_role text;
  enabled boolean;
begin
  if uid is null or not private.account_access_allowed() then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select cm.company_id,cm.role::text into cid,member_role
  from public.company_members cm where cm.user_id=uid limit 1;
  if cid is null or member_role is null or member_role not in ('owner','admin') then
    raise exception 'owner or admin permission required' using errcode='42501';
  end if;
  select c.company_seal_enabled into enabled
  from public.companies c where c.id=cid;
  if not found then raise exception 'company not found'; end if;
  return jsonb_build_object('company_seal_enabled',enabled);
end;
$function$;

create function public.save_company_seal_settings(p_enabled boolean)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  uid uuid:=auth.uid();
  cid uuid;
  member_role text;
  enabled boolean;
begin
  if uid is null or not private.account_access_allowed() then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select cm.company_id,cm.role::text into cid,member_role
  from public.company_members cm where cm.user_id=uid limit 1;
  if cid is null or member_role is null or member_role not in ('owner','admin') then
    raise exception 'owner or admin permission required' using errcode='42501';
  end if;
  if p_enabled is null then
    raise exception 'company seal setting is required' using errcode='22004';
  end if;
  update public.companies c
  set company_seal_enabled=p_enabled,updated_at=now()
  where c.id=cid returning c.company_seal_enabled into enabled;
  if not found then raise exception 'company not found'; end if;
  return jsonb_build_object('company_seal_enabled',enabled);
end;
$function$;

revoke all on function public.company_seal_settings() from public,anon;
revoke all on function public.save_company_seal_settings(boolean) from public,anon;
grant execute on function public.company_seal_settings() to authenticated;
grant execute on function public.save_company_seal_settings(boolean) to authenticated;

create or replace function public.invoice_document_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;

  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id,'can_view_invoices') then
    raise exception 'invoice view permission required';
  end if;

  select jsonb_build_object(
    'company_name', c.name,
    'company_seal_enabled', c.company_seal_enabled,
    'company_postal_code', coalesce(c.postal_code,''),
    'company_address', coalesce(c.address,''),
    'company_phone', coalesce(c.phone,''),
    'company_fax', coalesce(c.fax,''),
    'tax_rate', c.tax_rate,
    'welfare_rate', c.default_welfare_rate,
    'template_title', c.invoice_template_title,
    'footer_note', coalesce(c.invoice_footer_note,''),
    'bank_name', coalesce(b.bank_name,''),
    'bank_branch', coalesce(b.bank_branch,''),
    'bank_account_type', coalesce(b.bank_account_type,''),
    'bank_account_number', coalesce(b.bank_account_number,''),
    'bank_account_holder', coalesce(b.bank_account_holder,''),
    'invoice_subject', coalesce(b.invoice_subject,''),
    'invoice_contact_name', coalesce(b.invoice_contact_name,''),
    'payment_due_text', coalesce(b.payment_due_text,''),
    'invoice_logo_base64', coalesce(b.invoice_logo_base64,''),
    'invoice_seal_base64', coalesce(b.invoice_seal_base64,'')
  )
  into v_result
  from public.companies c
  left join public.company_private_billing_settings b on b.company_id=c.id
  where c.id=v_company_id;

  return coalesce(v_result,'{}'::jsonb);
end;
$function$;

revoke all on function public.invoice_document_settings() from public, anon;
grant execute on function public.invoice_document_settings() to authenticated;

create or replace function private.payroll_document_metadata(p_statement_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
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
$$;
