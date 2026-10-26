CREATE OR REPLACE FUNCTION private.expense_cost_finalize()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare row_data jsonb:=to_jsonb(new); previous jsonb; kind text; category text; subject uuid;
 first_day date; last_day date; done boolean; was_done boolean; component jsonb; claim jsonb;
 captured private.expense_amount_consumptions%rowtype;
begin
 if tg_op='UPDATE' then previous:=to_jsonb(old);end if;
 if tg_table_name='invoices' then
  kind:='invoice';category:='customer';subject:=(row_data->>'customer_id')::uuid;
  first_day:=(row_data->>'billing_period_start')::date;last_day:=(row_data->>'billing_period_end')::date;
  done:=row_data->>'status'<>'draft' or row_data->>'finalized_at' is not null or row_data->>'approval_finalized_at' is not null;
  was_done:=previous->>'status'<>'draft' or previous->>'finalized_at' is not null or previous->>'approval_finalized_at' is not null;
 else
  kind:='paymentCertificate';category:='subcontractor';subject:=(row_data->>'partner_company_id')::uuid;
  first_day:=(row_data->>'period_start')::date;last_day:=(row_data->>'period_end')::date;
  done:=row_data->>'status'='finalized';was_done:=previous->>'status'='finalized';
 end if;
 if not coalesce(done,false) or coalesce(was_done,false) then return new;end if;
 perform private.expense_cost_scope_lock(new.company_id,category,subject,first_day);
 -- Stabilize both the saved request and its explicit settlement decision.
 perform e.id from private.expense_claims e join private.expense_settlement_choices s on s.claim_id=e.id
 where e.company_id=new.company_id and e.incurred_on between first_day and last_day
 and s.cost_allocation_current and e.allocation=category and e.counterparty_id=subject order by e.id for share of e,s;
 component:=private.expense_cost_components(kind,new.company_id,subject,first_day,last_day,new.id);

 if kind='paymentCertificate' and new.snapshot?'expense_cost_direction_v2' then
 if new.snapshot->'expense_cost_direction_v2' is distinct from private.expense_payment_v2_envelope(new.company_id,new.id,subject,first_day,(row_data->>'revision')::integer,(component->>'amount_yen')::numeric,component->'claims')
 then raise exception 'v2 allocated expenses changed' using errcode='40001';end if;
 elsif (component->>'has_choices')::boolean or new.snapshot->>'expense_extra_source_version'='1' then
 
  if coalesce((new.snapshot->>'expense_extra_amount_yen')::numeric,0)<>(component->>'amount_yen')::numeric
   or coalesce(new.snapshot->'expense_extra_claims','[]') is distinct from component->'claims' then
   raise exception '経費が更新されました。下書きを再取得してから確定してください。' using errcode='40001';end if;
 end if;
 for claim in select value from jsonb_array_elements(component->'claims') loop
  select * into captured from private.expense_amount_consumptions where claim_id=(claim->>'id')::uuid and purpose='cost_recovery';
  if found and (captured.document_kind is distinct from kind or captured.document_id is distinct from new.id or (kind='paymentCertificate' and new.snapshot?'expense_cost_direction_v2' and (captured.company_id is distinct from new.company_id or captured.document_revision is distinct from (row_data->>'revision')::integer or captured.claim_revision is distinct from (claim->>'revision')::integer or captured.amount_yen is distinct from (claim->>'amount_yen')::integer))) then
   raise exception '経費は別の帳票へ計上済みです。' using errcode='22023';end if;
  insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
  values((claim->>'id')::uuid,'cost_recovery',new.company_id,kind,new.id,coalesce((row_data->>'revision')::integer,1),(claim->>'revision')::integer,(claim->>'amount_yen')::integer,claim)
  on conflict(claim_id,purpose) do nothing;
 end loop;
 return new;
end $function$;

