-- REVIEW ONLY. Owner-operated explicit conversion; no public RPC or product migration.
-- Requires the direction-v2 backend candidate; both gates default OFF.
create function private.expense_direction_v2_client_rollout_verified(cid uuid) returns boolean
language sql stable security invoker set search_path='' as $$select false$$;
revoke all on function private.expense_direction_v2_client_rollout_verified(uuid) from public,anon,authenticated;

-- An operator must export this exact before_row and verify restore before execution.
-- RLS without policies + revoked privileges keep this audit out of client APIs.
create table private.expense_payment_direction_conversions(
 document_id uuid primary key, company_id uuid not null, subject_id uuid not null,
 month date not null, source_revision integer not null, source_hash text not null,
 before_row jsonb not null, after_row jsonb not null, backup_reference text not null,
 rollout_reference text not null, actor_id uuid not null, converted_at timestamptz not null default now()
);
alter table private.expense_payment_direction_conversions enable row level security;
revoke all on private.expense_payment_direction_conversions from public,anon,authenticated;

create function private.expense_payment_conversion_audit_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$begin raise exception 'conversion original and receipt are immutable';end $$;
revoke all on function private.expense_payment_conversion_audit_immutable() from public,anon,authenticated;
create trigger expense_payment_conversion_audit_immutable before update or delete on private.expense_payment_direction_conversions
for each row execute function private.expense_payment_conversion_audit_immutable();

create function private.convert_payment_expense_v1_draft(
 cid uuid, doc uuid, subject uuid, month_day date, expected_revision integer,
 expected_source jsonb, expected_hash text, backup_reference text, rollout_reference text
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare old_row public.payment_certificates%rowtype; result public.payment_certificates%rowtype;
 audit private.expense_payment_direction_conversions%rowtype; component jsonb; envelope jsonb;
 rows_now jsonb; gross numeric; amount numeric; first_day date:=date_trunc('month',month_day)::date;
 last_day date:=(date_trunc('month',month_day)+interval '1 month - 1 day')::date;
 next_revision integer; next_snapshot jsonb;
begin
 if cid is null or doc is null or subject is null or month_day is null or month_day<>first_day
 or expected_revision is null or expected_revision<1 or expected_revision>=2147483647
 or jsonb_typeof(expected_source) is distinct from 'object'
 or expected_hash is null or expected_hash!~'^[0-9a-f]{32}$'
 or md5(expected_source::text) is distinct from expected_hash
 or coalesce(length(trim(backup_reference)),0)=0 or coalesce(length(trim(rollout_reference)),0)=0
 then raise exception 'explicit conversion request differs';end if;
 if auth.uid() is null or private.account_access_allowed() is not true
 or not exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role::text in ('owner','admin','manager'))
 then raise exception 'explicit conversion actor denied' using errcode='42501';end if;
 if private.expense_cost_direction_v2_enabled(cid) is not true
 or private.expense_direction_v2_client_rollout_verified(cid) is not true
 then raise exception 'direction consumer rollout is not verified';end if;
 perform private.expense_cost_scope_lock(cid,'subcontractor',subject,first_day);
 select * into old_row from public.payment_certificates where id=doc for update;
 if not found or old_row.company_id is distinct from cid or old_row.partner_company_id is distinct from subject
 or old_row.period_start is distinct from first_day or old_row.period_end is distinct from last_day
 then raise exception 'explicit conversion scope differs';end if;
 select * into audit from private.expense_payment_direction_conversions where document_id=doc;
 if found then
 if audit.company_id is distinct from cid or audit.subject_id is distinct from subject or audit.month is distinct from first_day
 or audit.source_revision is distinct from expected_revision or audit.source_hash is distinct from expected_hash
 or audit.before_row is distinct from expected_source or audit.backup_reference is distinct from backup_reference
 or audit.rollout_reference is distinct from rollout_reference or audit.after_row is distinct from to_jsonb(old_row)
 then raise exception 'conversion retry differs from saved receipt';end if;
 return audit.after_row;
 end if;
 if old_row.status is distinct from 'draft' or old_row.automatic_calculation is not true
 or old_row.calculation_blocked is distinct from false or old_row.revision is distinct from expected_revision
 or to_jsonb(old_row) is distinct from expected_source or md5(to_jsonb(old_row)::text) is distinct from expected_hash
 then raise exception 'conversion requires exact unchanged automatic draft';end if;
 if old_row.snapshot?'expense_cost_direction_v2' or old_row.snapshot?'expense_cost_basis'
 or old_row.snapshot->'expense_extra_source_version' is distinct from '1'::jsonb
 then raise exception 'explicit legacy v1 source required';end if;
 -- Lock the same source claims/choices as finalization; retain requester settlement unchanged.
 perform e.id from private.expense_claims e join private.expense_settlement_choices s on s.claim_id=e.id
 where e.company_id=cid and e.incurred_on between first_day and last_day
 and s.cost_allocation_current and e.allocation='subcontractor' and e.counterparty_id=subject
 order by e.id for share of e,s;
 if exists(select 1 from private.expense_amount_consumptions where company_id=cid and document_kind='paymentCertificate' and document_id=doc)
 or exists(select 1 from private.expense_amount_consumptions c join jsonb_array_elements(old_row.snapshot->'expense_extra_claims') e on c.claim_id=(e->>'id')::uuid where c.purpose='cost_recovery')
 then raise exception 'consumed legacy source cannot convert';end if;
 component:=private.expense_cost_components('paymentCertificate',cid,subject,first_day,last_day,doc);
 amount:=(component->>'amount_yen')::numeric;
 if old_row.snapshot->'expense_extra_amount_yen' is distinct from to_jsonb(amount)
 or old_row.snapshot->'expense_extra_claims' is distinct from component->'claims'
 then raise exception 'legacy allocated expenses changed';end if;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb),coalesce(sum(r.amount_yen),0)
 into rows_now,gross from private.certificate_calculation_rows(cid,subject,first_day,last_day) r;
 if old_row.snapshot->'calculation_rows' is distinct from rows_now or gross<0 or gross<>trunc(gross)
 or amount<=0 or amount<>trunc(amount) or gross+amount>2147483647
 or old_row.gross_amount is distinct from (gross+amount)::integer
 or old_row.deductions is distinct from 0 or old_row.net_amount is distinct from (gross+amount)::integer
 then raise exception 'legacy calculation basis differs';end if;
 next_revision:=expected_revision+1;
 envelope:=private.expense_payment_v2_envelope(cid,doc,subject,first_day,next_revision,amount,component->'claims');
 next_snapshot:=(old_row.snapshot-'expense_extra_source_version'-'expense_extra_amount_yen'-'expense_extra_claims')
 ||jsonb_build_object('expense_cost_direction_v2',envelope,'expense_cost_basis',jsonb_build_object(
 'company_id',cid,'document_id',doc,'subject_id',subject,'month',to_char(first_day,'YYYY-MM'),
 'document_revision',next_revision,'gross_before_expense_yen',gross,'other_deductions_yen',0));
 -- The existing v2 guard verifies the saved scope/basis/net. No finalization or consumption here.
 update public.payment_certificates set snapshot=next_snapshot,gross_amount=gross::integer,deductions=amount::integer,
 net_amount=(gross-amount)::integer,revision=next_revision,updated_at=now() where id=doc returning * into result;
 insert into private.expense_payment_direction_conversions(document_id,company_id,subject_id,month,source_revision,source_hash,
 before_row,after_row,backup_reference,rollout_reference,actor_id)
 values(doc,cid,subject,first_day,expected_revision,expected_hash,expected_source,to_jsonb(result),backup_reference,rollout_reference,auth.uid());
 return to_jsonb(result);
end $$;
revoke all on function private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text) from public,anon,authenticated;
