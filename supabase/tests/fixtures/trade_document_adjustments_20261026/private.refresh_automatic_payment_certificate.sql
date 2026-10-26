CREATE OR REPLACE FUNCTION private.refresh_automatic_payment_certificate(cid uuid, partner uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 expense_component jsonb; expense_amount numeric:=0;
 first_day date:=date_trunc('month',day)::date;
 last_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
 existing public.payment_certificates%rowtype;
 settings public.partner_payment_settings%rowtype;
 attendance_count int:=0;
 gross numeric:=0;
 subtotal numeric:=0;
 welfare numeric:=0;
 tax numeric:=0;
 partner_name text;
 snapshot_value jsonb;
 use_v2 boolean; direction_doc uuid; direction_revision integer;
 expense_deductions numeric:=0; expense_net numeric;
 calculation_rows jsonb;
 s record;
 allowance_cfg record;
 allowance_qty numeric;
 allowance_rate numeric;
 hours_per_day numeric:=8;
 overtime_mul numeric:=1.25;
 early_mul numeric:=1.25;
 night_mul numeric:=1.5;
 night_ot_mul numeric:=1.5;
 holiday_mul numeric:=1.35;
 holiday_ot_mul numeric:=1.35;
 holiday_night_mul numeric:=1.6;
 holiday_night_ot_mul numeric:=1.6;
 r_daily numeric:=0;
 r_ot numeric:=0;
 r_early numeric:=0;
 r_night numeric:=0;
 r_night_ot numeric:=0;
 r_holiday numeric:=0;
 r_holiday_ot numeric:=0;
 r_holiday_night numeric:=0;
 r_holiday_night_ot numeric:=0;
begin
 if auth.uid() is null or partner is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'payment-certificate:'||cid::text||partner::text||first_day::text,0
 ));

 select * into existing
 from public.payment_certificates
 where company_id=cid and partner_company_id=partner
   and period_start=first_day and period_end=last_day
 for update;
 if found and (existing.status<>'draft' or not existing.automatic_calculation) then return; end if;
 if existing.snapshot?'expense_cost_direction_v2' and not private.expense_cost_direction_v2_enabled(cid) then return;end if;
 use_v2:=private.expense_cost_direction_v2_enabled(cid) and (existing.id is null or existing.snapshot?'expense_cost_direction_v2');
 direction_doc:=coalesce(existing.id,gen_random_uuid());direction_revision:=coalesce(existing.revision,1);

 select * into settings
 from public.partner_payment_settings
 where company_id=cid and partner_company_id=partner;

 select pc.name into partner_name
 from public.partner_companies pc
 where pc.id=partner and pc.company_id=cid;

 select count(*) into attendance_count
 from public.attendance_entries a
 join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
 where a.company_id=cid
   and w.partner_company_id=partner
   and a.work_date between first_day and last_day;

 
 expense_component:=private.expense_cost_components('paymentCertificate',cid,partner,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
 if attendance_count=0 and not (expense_component->>'has_choices')::boolean
  and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.payment_certificates set gross_amount=0,deductions=0,net_amount=0,
   snapshot=existing.snapshot||jsonb_build_object('calculation_rows','[]'::jsonb,'attendance_count',0,
    'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=false,revision=revision+1,updated_at=now() where id=existing.id;
  return;
 end if;
 if attendance_count=0 and not (expense_component->>'has_choices')::boolean and (not use_v2 or existing.id is null) then
 
   if existing.id is not null and existing.status='draft'
      and existing.automatic_calculation then
     delete from public.payment_certificates where id=existing.id;
   end if;
   return;
 end if;

 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb),coalesce(sum(r.amount_yen),0)
 into calculation_rows,gross
 from private.certificate_calculation_rows(cid,partner,first_day,last_day) r;

 if use_v2 then expense_deductions:=expense_amount;else gross:=gross+expense_amount;end if;
 expense_net:=gross-expense_deductions;
 snapshot_value:=jsonb_build_object(
   'partner_company_name',coalesce(partner_name,''),
   'period_start',first_day,'period_end',last_day,
   'attendance_count',attendance_count,
   'settings_missing',settings.partner_company_id is null,
   'rate_formula',coalesce(settings.rate_formula,'{}'::jsonb),
   'welfare_rate',coalesce(settings.welfare_rate,0),
   'tax_rate',coalesce(settings.tax_rate,10),
   'calculation_rows',calculation_rows,
   'calculation_version',2
 );

 
 if use_v2 then
 snapshot_value:=snapshot_value||jsonb_build_object(
 'expense_cost_direction_v2',private.expense_payment_v2_envelope(cid,direction_doc,partner,first_day,direction_revision,expense_amount,expense_component->'claims'),
 'expense_cost_basis',jsonb_build_object('company_id',cid,'document_id',direction_doc,'subject_id',partner,'month',to_char(first_day,'YYYY-MM'),'document_revision',direction_revision,'gross_before_expense_yen',gross,'other_deductions_yen',0));
 elsif coalesce((expense_component->>'has_choices')::boolean,false) or existing.snapshot?'expense_extra_source_version' then
  snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
   'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 end if;
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 (existing.snapshot,cid,existing.id is null);
  if existing.id is null then
   insert into public.payment_certificates(
     id,company_id,partner_company_id,period_start,period_end,status,
     gross_amount,deductions,net_amount,snapshot,
     automatic_calculation,calculation_blocked
   )
   values(
     direction_doc,cid,partner,first_day,last_day,'draft',
     gross::int,expense_deductions::int,expense_net::int,snapshot_value,true,false
   );
 elsif existing.gross_amount is distinct from gross::int
    or existing.net_amount is distinct from expense_net::int
    or (use_v2 and existing.deductions is distinct from expense_deductions::int)
    or existing.snapshot is distinct from snapshot_value
    or existing.calculation_blocked then
   update public.payment_certificates
   set gross_amount=gross::int,deductions=expense_deductions::int,net_amount=expense_net::int,
       snapshot=case when use_v2 then jsonb_set(jsonb_set(snapshot_value,'{expense_cost_direction_v2,document_revision}',to_jsonb(existing.revision+1)),'{expense_cost_basis,document_revision}',to_jsonb(existing.revision+1)) else snapshot_value end,calculation_blocked=false,
       revision=revision+1,updated_at=now()
   where id=existing.id;
 end if;
end
$function$
;
