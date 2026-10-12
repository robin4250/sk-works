-- Forward extension of the deployed metadata contract; never recreates tables.
alter table private.expense_settlement_choices
 add column approval_current boolean not null default false;
-- Reuse an authenticated immutable approval receipt, never infer from allocation.
update private.expense_settlement_choices s set approval_current=true
from private.expense_claims e
where e.id=s.claim_id and e.company_id=s.company_id and e.approval='approved' and not e.withdrawn
 and exists(select 1 from private.expense_settlement_events v where v.claim_id=e.id and v.company_id=e.company_id
  and (v.result->>'revision')::integer=s.revision and v.command->>'method'=s.method
  and (v.command->>'settlement_month')::date=s.settlement_month
  and v.result->>'amount_yen'=e.amount_yen::text
  and v.result->>'incurred_on'=e.incurred_on::text
  and v.result->>'description'=e.description
  and v.result->>'applicant_id'=e.applicant_id::text
  and v.result->>'created_by'=e.created_by::text)
 and not exists(select 1 from private.expense_personal_changes c where c.claim_id=e.id and (c.result->>'revision')::integer>s.revision)
 and not exists(select 1 from private.expense_claim_events c where c.claim_id=e.id and c.command->>'action'='reject' and (c.result->>'revision')::integer>s.revision);

create or replace function private.expense_approve_with_settlement(
 p_command_id uuid,p_claim uuid,p_revision integer,p_method text,p_settlement_month date
) returns jsonb language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; old private.expense_settlement_events%rowtype;
 choice private.expense_settlement_choices%rowtype; result jsonb;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'method',p_method,'settlement_month',p_settlement_month);
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501';end if;
 -- Preserve the existing company -> approver settings -> claim lock order.
 perform 1 from public.companies where id=claim.company_id for key share;
 perform 1 from private.expense_approval_settings where company_id=claim.company_id for share;
 if not coalesce((private.expense_review_access(claim.company_id)->>'can_review')::boolean,false) then
  raise exception 'selected expense approver required' using errcode='42501';end if;
 if not exists(select 1 from public.company_members m where m.company_id=claim.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager')) then
  raise exception '精算方法は管理者・サブ管理者が設定してください。' using errcode='42501';end if;
 if p_command_id is null or p_method is null or p_method not in ('cash','payroll') or p_settlement_month is null or extract(day from p_settlement_month)<>1 or p_settlement_month < date '1900-01-01' or p_settlement_month > date '9999-12-01' then
  raise exception '精算方法と対象月を選択してください。' using errcode='22023';end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into old from private.expense_settlement_events where command_id=p_command_id;
 if found then
  if old.actor_id is distinct from auth.uid() or old.command is distinct from command then
   raise exception 'fixed expense settlement command differs' using errcode='23505';end if;
  return old.result;
 end if;
 if claim.revision is distinct from p_revision then raise exception 'expense changed; reload' using errcode='40001';end if;
 if claim.withdrawn then raise exception 'withdrawn expense unavailable' using errcode='22023';end if;
 perform private.expense_cost_scope_lock(claim.company_id,claim.allocation,claim.counterparty_id,claim.incurred_on);
 select * into choice from private.expense_settlement_choices where claim_id=p_claim;
 if found and claim.approval='approved' and choice.approval_current and
  (choice.method is distinct from p_method or choice.settlement_month is distinct from p_settlement_month) then
  raise exception '承認済みの精算方法を再送で変更できません。' using errcode='22023';end if;
 -- Existing approval checks, self-review policy, immutable command and allocation.
 result:=private.expense_review_command(p_command_id,p_claim,p_revision,'approve',null,null);
 insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current)
 values(p_claim,claim.company_id,p_method,p_settlement_month,(result->>'revision')::integer,auth.uid(),true)
 on conflict(claim_id) do update set method=excluded.method,settlement_month=excluded.settlement_month,
  revision=excluded.revision,approval_current=true,chosen_by=excluded.chosen_by,chosen_at=clock_timestamp()
 where expense_settlement_choices.method is distinct from excluded.method
  or expense_settlement_choices.settlement_month is distinct from excluded.settlement_month
  or not expense_settlement_choices.approval_current;
 result:=result||jsonb_build_object('settlement_method',p_method,'settlement_month',p_settlement_month);
 insert into private.expense_settlement_events(command_id,claim_id,company_id,actor_id,command,result)
 values(p_command_id,p_claim,claim.company_id,auth.uid(),command,result);
 return result;
end $$;
create or replace function private.expense_settlement_workspace(p_company uuid,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare workspace jsonb; claims jsonb;
begin
 workspace:=private.expense_review_workspace(p_company,p_month);
 select coalesce(jsonb_agg(x.claim||jsonb_build_object('settlement_method',case when x.claim->>'approval'='approved' and not s.approval_current then null else s.method end,'settlement_month',case when x.claim->>'approval'='approved' and not s.approval_current then null else s.settlement_month end) order by x.ordinality),'[]')
 into claims from jsonb_array_elements(workspace->'claims') with ordinality x(claim,ordinality)
 left join private.expense_settlement_choices s on s.claim_id=(x.claim->>'id')::uuid and s.company_id=p_company;
 return workspace||jsonb_build_object('claims',claims,'settlement_choice_enabled',true,'cost_allocation_enabled',true,'can_settle',
  coalesce((workspace->>'can_review')::boolean,false) and exists(select 1 from public.company_members m where m.company_id=p_company and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager')));
end $$;
create or replace function public.expense_approve_with_settlement(p_command_id uuid,p_claim uuid,p_revision integer,p_method text,p_settlement_month date)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_approve_with_settlement(p_command_id,p_claim,p_revision,p_method,p_settlement_month)$$;
create or replace function public.expense_settlement_workspace(p_company uuid,p_month date)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_settlement_workspace(p_company,p_month)$$;
create or replace function private.expense_personal_settlement_history(p_company uuid,p_worker uuid,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare history jsonb; result jsonb;
begin
 history:=private.expense_personal_history(p_company,p_worker,p_month);
 select coalesce(jsonb_agg(x.claim||jsonb_build_object('settlement_method',case when x.claim->>'approval'='approved' and not s.approval_current then null else s.method end,'settlement_month',case when x.claim->>'approval'='approved' and not s.approval_current then null else s.settlement_month end) order by x.ordinality),'[]')
 into result from jsonb_array_elements(history) with ordinality x(claim,ordinality)
 left join private.expense_settlement_choices s on s.claim_id=(x.claim->>'id')::uuid and s.company_id=p_company;
 return result;
end $$;
create or replace function public.expense_personal_settlement_history(p_company uuid,p_worker uuid,p_month date)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_settlement_history(p_company,p_worker,p_month)$$;
revoke all on function private.expense_personal_settlement_history(uuid,uuid,date),public.expense_personal_settlement_history(uuid,uuid,date) from public,anon;
grant execute on function private.expense_personal_settlement_history(uuid,uuid,date),public.expense_personal_settlement_history(uuid,uuid,date) to authenticated;
revoke all on function private.expense_approve_with_settlement(uuid,uuid,integer,text,date),public.expense_approve_with_settlement(uuid,uuid,integer,text,date),private.expense_settlement_workspace(uuid,date),public.expense_settlement_workspace(uuid,date) from public,anon;
grant execute on function private.expense_approve_with_settlement(uuid,uuid,integer,text,date),public.expense_approve_with_settlement(uuid,uuid,integer,text,date),private.expense_settlement_workspace(uuid,date),public.expense_settlement_workspace(uuid,date) to authenticated;
