CREATE OR REPLACE FUNCTION private.read_expense_document(p_kind text, p_document uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare row_data jsonb; cid uuid; subject uuid; expense_month date; version integer; live boolean; allowed boolean:=false; claims jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'account unavailable' using errcode='42501'; end if;
 if p_kind='payroll' then select to_jsonb(p) into row_data from public.payroll_statements p where id=p_document;
 elsif p_kind='invoice' then select to_jsonb(p) into row_data from public.invoices p where id=p_document;
 elsif p_kind='paymentCertificate' then select to_jsonb(p) into row_data from public.payment_certificates p where id=p_document;
 else raise exception 'invalid expense document kind' using errcode='22023'; end if;
 if row_data is null then raise exception 'document unavailable' using errcode='42501'; end if;
 cid:=(row_data->>'company_id')::uuid;version:=coalesce((row_data->>'revision')::integer,1);
 if p_kind='payroll' then
  subject:=(row_data->>'worker_id')::uuid;expense_month:=(row_data->>'period_end')::date;live:=row_data->>'workflow_state'='draft';
  allowed:=exists(select 1 from public.workers w where w.id=subject and w.company_id=cid and w.user_id=auth.uid()) or exists(
   select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and
   (m.role::text in ('owner','admin','viewer') or (m.role::text='manager' and exists(select 1 from public.payroll_manager_worker_visibility v where v.company_id=cid and v.worker_id=subject and v.visible_to_manager)))
  );
 elsif p_kind='invoice' then
  subject:=(row_data->>'customer_id')::uuid;expense_month:=(row_data->>'billing_period_start')::date;live:=row_data->>'status'='draft' and row_data->>'finalized_at' is null;
  allowed:=private.has_company_feature(cid,'can_view_invoices');
 else
  subject:=(row_data->>'partner_company_id')::uuid;expense_month:=(row_data->>'period_start')::date;live:=row_data->>'status'='draft';
  allowed:=exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'));
 end if;
 if not coalesce(allowed,false) or not exists(select 1 from public.companies where id=cid) then raise exception 'document access denied' using errcode='42501'; end if;
 if live then claims:=private.expense_document_claims(p_kind,cid,subject,expense_month);
 else
  select s.claims into claims from private.expense_document_snapshots s where s.kind=p_kind and s.document_id=p_document and s.revision=version and s.company_id=cid and s.subject_id=subject and s.month=date_trunc('month',expense_month)::date;
 end if;
 
 if p_kind in ('invoice','paymentCertificate')
  and row_data->'snapshot'->>'expense_extra_source_version'='1' then
  select coalesce(jsonb_agg(c.value order by c.ordinality),'[]'::jsonb) into claims
  from jsonb_array_elements(coalesce(claims,'[]'::jsonb)) with ordinality c(value,ordinality)
  where exists(select 1 from jsonb_array_elements(coalesce(row_data->'snapshot'->'expense_extra_claims','[]'::jsonb)) s(value)
   where s.value->>'id'=c.value->>'id' and s.value->>'revision'=c.value->>'revision'
    and s.value->>'amount_yen'=c.value->>'amount_yen');
  if jsonb_array_length(claims)<>jsonb_array_length(coalesce(row_data->'snapshot'->'expense_extra_claims','[]'::jsonb))
   or (select coalesce(sum((c.value->>'amount_yen')::numeric),0) from jsonb_array_elements(claims) c(value))
    <>coalesce((row_data->'snapshot'->>'expense_extra_amount_yen')::numeric,0) then
   raise exception '経費の内訳と帳票金額が変わりました。再読み込みしてください。' using errcode='40001';
  end if;
 end if;
 

 if p_kind='paymentCertificate' and row_data->'snapshot'?'expense_cost_direction_v2' then
 if private.payment_expense_v2_requested() IS NOT TRUE
 then raise exception 'Update SKO to read directional expenses' using errcode='42501'; end if;
 select coalesce(jsonb_agg(c.value order by c.ordinality),'[]') into claims
 from jsonb_array_elements(coalesce(claims,'[]')) with ordinality c(value,ordinality)
 where exists(select 1 from jsonb_array_elements(row_data->'snapshot'->'expense_cost_direction_v2'->'claims') s(value)
 where s.value->>'id'=c.value->>'id' and s.value->>'revision'=c.value->>'revision' and s.value->>'amount_yen'=c.value->>'amount_yen');
 if row_data->'snapshot'->'expense_cost_direction_v2' is distinct from private.expense_payment_v2_envelope(cid,p_document,subject,expense_month,version,
 (row_data->'snapshot'->'expense_cost_direction_v2'->>'amount_yen')::numeric,claims)
 then raise exception 'v2 details differ from saved scope/version' using errcode='40001';end if;
 return jsonb_build_object('kind',p_kind,'document_id',p_document,'company_id',cid,'subject_id',subject,'month',date_trunc('month',expense_month)::date,
 'revision',version,'updated_at',row_data->'updated_at','frozen',not coalesce(live,false),'claims',claims,
 'cost_recovery_amount_yen',(row_data->'snapshot'->'expense_cost_direction_v2'->>'amount_yen')::integer,
 'expense_cost_direction_v2',row_data->'snapshot'->'expense_cost_direction_v2','expense_cost_basis',row_data->'snapshot'->'expense_cost_basis');
 end if;
 return jsonb_build_object('kind'
 
 ,p_kind,'document_id',p_document,'company_id',cid,'subject_id',subject,'month',date_trunc('month',expense_month)::date,'revision',version,'updated_at',row_data->'updated_at','frozen',not coalesce(live,false),'cost_recovery_amount_yen',case when p_kind in ('invoice','paymentCertificate') and row_data->'snapshot'->>'expense_extra_source_version'='1' then (row_data->'snapshot'->>'expense_extra_amount_yen')::integer else null end,'claims',coalesce(claims,'[]'::jsonb));
end $function$;

