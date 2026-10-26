CREATE OR REPLACE FUNCTION private.expense_payment_v2_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare envelope jsonb:=new.snapshot->'expense_cost_direction_v2';basis jsonb;expected jsonb;gross numeric;
begin
 if tg_op='DELETE' then
 if old.snapshot?'expense_cost_direction_v2' and old.status='finalized' then raise exception 'finalized v2 payment immutable';end if;
 return old;end if;
 if tg_op='UPDATE' and old.snapshot?'expense_cost_direction_v2' then
 if not new.snapshot?'expense_cost_direction_v2' then raise exception 'v2 downgrade refused';end if;
 if old.status='finalized' and (to_jsonb(old)-'updated_at') is distinct from (to_jsonb(new)-'updated_at') then raise exception 'finalized v2 payment immutable';end if;
 end if;
 if not new.snapshot?'expense_cost_direction_v2' then return new;end if;
 if not new.automatic_calculation or new.snapshot?'expense_extra_source_version'
 or new.snapshot?'expense_extra_amount_yen' or new.snapshot?'expense_extra_claims'
 then raise exception 'mixed or manual v2 expense source refused';end if;
 if new.company_id is null or new.id is null or new.partner_company_id is null or new.period_start is null or new.period_end is null
 or new.revision is null or new.gross_amount is null or new.deductions is null or new.net_amount is null
 or jsonb_typeof(new.snapshot->'calculation_rows') is distinct from 'array'
 or jsonb_typeof(envelope) is distinct from 'object' or envelope->>'version' is distinct from '2'
 or new.period_start<>date_trunc('month',new.period_start)::date
 or new.period_end<>(date_trunc('month',new.period_start)+interval '1 month - 1 day')::date
 then raise exception 'v2 document period differs';end if;
 expected:=private.expense_payment_v2_envelope(new.company_id,new.id,new.partner_company_id,new.period_start,new.revision,
 (envelope->>'amount_yen')::numeric,envelope->'claims');
 if envelope is distinct from expected then raise exception 'v2 document scope or claims differ';end if;
 select coalesce(sum((r->>'amount_yen')::numeric),0) into gross from jsonb_array_elements(new.snapshot->'calculation_rows') r;
 basis:=jsonb_build_object('company_id',new.company_id,'document_id',new.id,'subject_id',new.partner_company_id,
 'month',to_char(new.period_start,'YYYY-MM'),'document_revision',new.revision,'gross_before_expense_yen',gross,'other_deductions_yen',0);
 if new.snapshot->'expense_cost_basis' is distinct from basis or gross<0 or new.gross_amount<>gross
 or new.deductions<>(envelope->>'amount_yen')::numeric or new.net_amount<>gross-new.deductions
 then raise exception 'v2 payment amount or calculation basis differs';end if;
 return new;
end $function$;

