-- Explicit approved additional expenses. Cost recovery and reimbursement are distinct.
-- No payroll generator updates, no historical backfill, no document deletions.
-- Existing settlement choices are not authorization to add money to documents.
alter table private.expense_settlement_choices
 add column cost_allocation_current boolean not null default false;
create table private.expense_amount_consumptions(
 claim_id uuid not null references private.expense_claims(id),
 purpose text not null check(purpose in ('cost_recovery','reimbursement')),
 company_id uuid not null,document_kind text not null,document_id uuid not null,
 document_revision integer not null,claim_revision integer not null,
 amount_yen integer not null check(amount_yen>0),snapshot jsonb not null,
 captured_at timestamptz not null default clock_timestamp(),primary key(claim_id,purpose)
);
alter table private.expense_amount_consumptions enable row level security;
revoke all on private.expense_amount_consumptions from public,anon,authenticated;
create index expense_amount_consumptions_document on private.expense_amount_consumptions(company_id,document_kind,document_id,document_revision);

create function private.expense_cost_components(p_kind text,cid uuid,subject uuid,first_day date,last_day date,p_document uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with scoped as (
  select e.*,s.method,s.settlement_month,s.approval_current,s.cost_allocation_current
  from private.expense_claims e join private.expense_settlement_choices s on s.claim_id=e.id and s.company_id=e.company_id
  where e.company_id=cid and s.cost_allocation_current and e.incurred_on between first_day and last_day
   and case p_kind when 'invoice' then e.allocation='customer' and e.counterparty_id=subject
   when 'paymentCertificate' then e.allocation='subcontractor' and e.counterparty_id=subject else false end
 ),eligible as (
  select e.* from scoped e where e.approval='approved' and e.approval_current and not e.withdrawn
   and not exists(select 1 from private.expense_amount_consumptions c where c.claim_id=e.id and c.purpose='cost_recovery'
    and (c.document_kind is distinct from p_kind or c.document_id is distinct from p_document))
 ) select jsonb_build_object('has_choices',exists(select 1 from scoped),
  'amount_yen',coalesce((select sum(amount_yen) from eligible),0),
  'claims',coalesce((select jsonb_agg(jsonb_build_object('id',id,'revision',revision,'applicant_id',applicant_id,
   'applicant_name',applicant_name,'incurred_on',incurred_on,'description',description,'amount_yen',amount_yen,
   'settlement_method',method,'settlement_month',settlement_month) order by incurred_on,id) from eligible),'[]'::jsonb))
$$;
revoke all on function private.expense_cost_components(text,uuid,uuid,date,date,uuid) from public,anon,authenticated;

create function private.expense_cost_scope_lock(cid uuid,category text,party uuid,day date)
returns void language plpgsql security definer set search_path='' as $$
declare key text;
begin
 if category='customer' then key:='invoice:';
 elsif category='subcontractor' then key:='payment-certificate:';
 else return;end if;
 if not pg_try_advisory_xact_lock(hashtextextended(key||cid::text||party::text||date_trunc('month',day)::date::text,0)) then
  raise exception '経費を帳票へ反映中です。再読み込みしてください。' using errcode='40001';end if;
end $$;
revoke all on function private.expense_cost_scope_lock(uuid,text,uuid,date) from public,anon,authenticated;

-- A new explicit command opts into financial recovery; legacy commands retain
-- their old meaning and never become authorization to add historical amounts.
create table private.expense_cost_allocation_events (
 command_id uuid primary key,claim_id uuid not null,company_id uuid not null,
 actor_id uuid not null,command jsonb not null,result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table private.expense_cost_allocation_events enable row level security;
revoke all on private.expense_cost_allocation_events from public,anon,authenticated;
create function private.expense_allocate_with_cost(p_command_id uuid,p_claim uuid,p_revision integer,p_allocation text,p_counterparty uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; receipt private.expense_cost_allocation_events%rowtype;
 command jsonb:=jsonb_build_object('claim',p_claim,'revision',p_revision,'allocation',p_allocation,'counterparty',p_counterparty);
 result jsonb; scope record; old_context text;
begin
 select * into claim from private.expense_claims where id=p_claim;
 if not found then raise exception 'expense unavailable' using errcode='42501';end if;
 perform 1 from public.companies where id=claim.company_id for key share;
 perform 1 from private.expense_approval_settings where company_id=claim.company_id for share;
 if not coalesce((private.expense_review_access(claim.company_id)->>'can_review')::boolean,false) then
  raise exception 'selected expense approver required' using errcode='42501';end if;
 select * into claim from private.expense_claims where id=p_claim for update;
 select * into receipt from private.expense_cost_allocation_events where command_id=p_command_id;
 if found then
  if receipt.actor_id is distinct from auth.uid() or receipt.command is distinct from command then
   raise exception 'fixed expense cost allocation differs' using errcode='23505';end if;
  return receipt.result;
 end if;
 if p_command_id is null or exists(select 1 from private.expense_claim_events where command_id=p_command_id) then
  raise exception 'new explicit allocation command required' using errcode='23505';end if;
 if claim.revision is distinct from p_revision then raise exception 'expense changed; reload' using errcode='40001';end if;
 if claim.approval<>'approved' or claim.withdrawn or not exists(select 1 from private.expense_settlement_choices
  where claim_id=p_claim and company_id=claim.company_id and approval_current) then
  raise exception '先に精算方法を選択して承認してください。' using errcode='22023';end if;
 for scope in select * from (values(claim.company_id,claim.allocation,claim.counterparty_id,claim.incurred_on),
  (claim.company_id,p_allocation,p_counterparty,claim.incurred_on)) x(cid,category,party,day)
  order by cid,category,party,day loop
  perform private.expense_cost_scope_lock(scope.cid,scope.category,scope.party,scope.day);
 end loop;
 if p_allocation='customer' and exists(select 1 from public.invoices where company_id=claim.company_id
  and customer_id=p_counterparty and billing_period_start=date_trunc('month',claim.incurred_on)::date
  and (status<>'draft' or finalized_at is not null or approval_finalized_at is not null or not automatic_calculation))
  or p_allocation='subcontractor' and exists(select 1 from public.payment_certificates where company_id=claim.company_id
  and partner_company_id=p_counterparty and period_start=date_trunc('month',claim.incurred_on)::date
  and (status<>'draft' or not automatic_calculation)) then
  raise exception '対象帳票は確定済みまたは手動編集です。振り分け先を確認してください。' using errcode='22023';end if;
 old_context:=current_setting('sko.expense_cost_allocation',true);
 perform set_config('sko.expense_cost_allocation','1',true);
 result:=private.expense_review_command(p_command_id,p_claim,p_revision,'allocate',p_allocation,p_counterparty);
 perform set_config('sko.expense_cost_allocation',coalesce(old_context,''),true);
 update private.expense_settlement_choices set cost_allocation_current=p_allocation in ('customer','subcontractor') where claim_id=p_claim;
 result:=result||jsonb_build_object('cost_allocation_current',p_allocation in ('customer','subcontractor'));
 insert into private.expense_cost_allocation_events(command_id,claim_id,company_id,actor_id,command,result)
 values(p_command_id,p_claim,claim.company_id,auth.uid(),command,result);
 return result;
end $$;
create function public.expense_allocate_with_cost(p_command_id uuid,p_claim uuid,p_revision integer,p_allocation text,p_counterparty uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select private.expense_allocate_with_cost(p_command_id,p_claim,p_revision,p_allocation,p_counterparty)
$$;
revoke all on function private.expense_allocate_with_cost(uuid,uuid,integer,text,uuid),public.expense_allocate_with_cost(uuid,uuid,integer,text,uuid) from public,anon;
grant execute on function private.expense_allocate_with_cost(uuid,uuid,integer,text,uuid),public.expense_allocate_with_cost(uuid,uuid,integer,text,uuid) to authenticated;

create function private.expense_cost_claim_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare scope record;
begin
 if not exists(select 1 from private.expense_settlement_choices where claim_id=old.id) then return new;end if;
 -- The row is already locked by UPDATE. Try, never wait on a finalizer holding its document.
 for scope in select * from (values(old.company_id,old.allocation,old.counterparty_id,old.incurred_on),
  (new.company_id,new.allocation,new.counterparty_id,new.incurred_on)) x(cid,category,party,day)
  order by cid,category,party,day loop
  perform private.expense_cost_scope_lock(scope.cid,scope.category,scope.party,scope.day);
 end loop;
 if exists(select 1 from private.expense_amount_consumptions where claim_id=old.id) and
  (new.company_id,new.applicant_id,new.incurred_on,new.description,new.amount_yen,new.approval,new.withdrawn,new.allocation,new.counterparty_id)
  is distinct from (old.company_id,old.applicant_id,old.incurred_on,old.description,old.amount_yen,old.approval,old.withdrawn,old.allocation,old.counterparty_id) then
  raise exception '経費は帳票確定済みです。確定済みの金額・振り分けを変更できません。' using errcode='22023';end if;
 if new.approval='approved' and new.revision is distinct from old.revision
  and current_setting('sko.expense_cost_allocation',true) is distinct from '1' then
  update private.expense_settlement_choices set cost_allocation_current=false where claim_id=old.id and cost_allocation_current;
 end if;
 if new.approval<>'approved' then
  update private.expense_settlement_choices set approval_current=false,cost_allocation_current=false where claim_id=old.id and (approval_current or cost_allocation_current);
 end if;
 return new;
end $$;
revoke all on function private.expense_cost_claim_guard() from public,anon,authenticated;
create trigger expense_cost_claim_guard before update on private.expense_claims for each row execute function private.expense_cost_claim_guard();

create function private.expense_cost_choice_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype;
begin
 select * into claim from private.expense_claims where id=new.claim_id;
 if not found or claim.company_id is distinct from new.company_id then raise exception 'expense settlement scope differs';end if;
 perform private.expense_cost_scope_lock(claim.company_id,claim.allocation,claim.counterparty_id,claim.incurred_on);
 if tg_op='UPDATE' and exists(select 1 from private.expense_amount_consumptions where claim_id=new.claim_id)
  and (new.method,new.settlement_month,new.approval_current,new.cost_allocation_current) is distinct from (old.method,old.settlement_month,old.approval_current,old.cost_allocation_current) then
  raise exception '経費は帳票確定済みです。精算設定を変更できません。' using errcode='22023';end if;
 return new;
end $$;
revoke all on function private.expense_cost_choice_guard() from public,anon,authenticated;
create trigger expense_cost_choice_guard before insert or update on private.expense_settlement_choices for each row execute function private.expense_cost_choice_guard();

create function private.expense_cost_refresh_scope(cid uuid,category text,party uuid,day date)
returns void language plpgsql security definer set search_path='' as $$
begin
 if category='customer' then
  if exists(select 1 from public.invoices where company_id=cid and customer_id=party and billing_period_start=date_trunc('month',day)::date
   and (status<>'draft' or finalized_at is not null or approval_finalized_at is not null or not automatic_calculation)) then
   return;end if;
  perform private.refresh_automatic_invoice(cid,party,day);
 elsif category='subcontractor' then
  if exists(select 1 from public.payment_certificates where company_id=cid and partner_company_id=party and period_start=date_trunc('month',day)::date
   and (status<>'draft' or not automatic_calculation)) then
   return;end if;
  perform private.refresh_automatic_payment_certificate(cid,party,day);
 end if;
end $$;
revoke all on function private.expense_cost_refresh_scope(uuid,text,uuid,date) from public,anon,authenticated;

create function private.expense_cost_refresh() returns trigger
language plpgsql security definer set search_path='' as $$
declare claim private.expense_claims%rowtype; scope record;
begin
 if tg_table_name='expense_settlement_choices' then
  select * into claim from private.expense_claims where id=new.claim_id;
  perform private.expense_cost_refresh_scope(claim.company_id,claim.allocation,claim.counterparty_id,claim.incurred_on);
 elsif exists(select 1 from private.expense_settlement_choices where claim_id=new.id) then
  for scope in select distinct * from (values(old.company_id,old.allocation,old.counterparty_id,old.incurred_on),
   (new.company_id,new.allocation,new.counterparty_id,new.incurred_on)) x(cid,category,party,day) order by cid,category,party,day loop
   perform private.expense_cost_refresh_scope(scope.cid,scope.category,scope.party,scope.day);
  end loop;
 end if;
 return new;
end $$;
revoke all on function private.expense_cost_refresh() from public,anon,authenticated;
create trigger expense_cost_refresh_claim after update on private.expense_claims for each row execute function private.expense_cost_refresh();
create trigger expense_cost_refresh_choice after insert or update on private.expense_settlement_choices for each row execute function private.expense_cost_refresh();

create function private.expense_cost_finalize() returns trigger
language plpgsql security definer set search_path='' as $$
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
 if (component->>'has_choices')::boolean or new.snapshot->>'expense_extra_source_version'='1' then
  if coalesce((new.snapshot->>'expense_extra_amount_yen')::numeric,0)<>(component->>'amount_yen')::numeric
   or coalesce(new.snapshot->'expense_extra_claims','[]') is distinct from component->'claims' then
   raise exception '経費が更新されました。下書きを再取得してから確定してください。' using errcode='40001';end if;
 end if;
 for claim in select value from jsonb_array_elements(component->'claims') loop
  select * into captured from private.expense_amount_consumptions where claim_id=(claim->>'id')::uuid and purpose='cost_recovery';
  if found and (captured.document_kind is distinct from kind or captured.document_id is distinct from new.id) then
   raise exception '経費は別の帳票へ計上済みです。' using errcode='22023';end if;
  insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
  values((claim->>'id')::uuid,'cost_recovery',new.company_id,kind,new.id,coalesce((row_data->>'revision')::integer,1),(claim->>'revision')::integer,(claim->>'amount_yen')::integer,claim)
  on conflict(claim_id,purpose) do nothing;
 end loop;
 return new;
end $$;
revoke all on function private.expense_cost_finalize() from public,anon,authenticated;
create trigger expense_cost_invoice_finalization before insert or update on public.invoices for each row execute function private.expense_cost_finalize();
create trigger expense_cost_certificate_finalization before insert or update on public.payment_certificates for each row execute function private.expense_cost_finalize();

-- Append the original expense amount after the existing taxable/welfare totals.
-- Preserve existing formulas, route quantities, seals and protected/manual documents.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure);
 if position('if n=0 then' in definition)=0 or position('total_pre_tax+total_tax' in definition)=0
  or position('snapshot_value:=snapshot_value||private.document_company_seal_snapshot' in definition)=0 then
  raise exception 'Current invoice anchors differ; inspect before applying';end if;
 definition:=replace(definition,E'declare\n',E'declare\n  expense_component jsonb; expense_amount numeric:=0;\n');
 definition:=replace(definition,'if n=0 then',$invoice$
 expense_component:=private.expense_cost_components('invoice',cid,customer,first_day,last_day,existing.id);
 expense_amount:=(expense_component->>'amount_yen')::numeric;
  if n=0 and expense_amount=0 and existing.id is not null and existing.snapshot?'expense_extra_source_version' then
  update public.invoices set subtotal=0,tax=0,welfare_amount=0,grand_total=0,
   snapshot=existing.snapshot||jsonb_build_object('sites','[]'::jsonb,'subtotal',0,'tax',0,'grand_total',0,
    'route_quantity_pending',route_blocked,'expense_extra_amount_yen',0,'expense_extra_claims','[]'::jsonb),
   calculation_blocked=route_blocked,updated_at=now() where id=existing.id;
  return;
 end if;
 if n=0 and expense_amount=0 then
 $invoice$);
 definition:=replace(definition,'total_pre_tax+total_tax','total_pre_tax+total_tax+expense_amount');
 definition:=replace(definition,'snapshot_value:=snapshot_value||private.document_company_seal_snapshot',$invoice$
 snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
  'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 $invoice$);
 execute definition;

 definition:=pg_get_functiondef('private.refresh_automatic_payment_certificate(uuid,uuid,date)'::regprocedure);
 if position('if attendance_count=0 then' in definition)=0
  or position('snapshot_value:=jsonb_build_object(' in definition)=0
  or position('snapshot_value:=snapshot_value||private.document_company_seal_snapshot' in definition)=0 then
  raise exception 'Current payment certificate anchors differ; inspect before applying';end if;
 definition:=replace(definition,E'declare\n',E'declare\n expense_component jsonb; expense_amount numeric:=0;\n');
 definition:=replace(definition,'if attendance_count=0 then',$certificate$
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
 if attendance_count=0 and not (expense_component->>'has_choices')::boolean then
 $certificate$);
 definition:=replace(definition,'snapshot_value:=jsonb_build_object(',E'gross:=gross+expense_amount;\n snapshot_value:=jsonb_build_object(');
 definition:=replace(definition,'snapshot_value:=snapshot_value||private.document_company_seal_snapshot',$certificate$
 snapshot_value:=snapshot_value||jsonb_build_object('expense_extra_amount_yen',expense_amount,
  'expense_extra_claims',expense_component->'claims','expense_extra_source_version',1);
 snapshot_value:=snapshot_value||private.document_company_seal_snapshot
 $certificate$);
 execute definition;
end $patch$;

-- New monetary snapshots must display exactly their charged expenses.
-- Preserve legacy detail-only documents and all existing read permissions.
do $detail_patch$
declare definition text; anchor text:='return jsonb_build_object(''kind''';
begin
 definition:=pg_get_functiondef('private.read_expense_document(text,uuid)'::regprocedure);
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Current expense detail reader anchor differs; inspect before applying';
 end if;
 definition:=replace(definition,anchor,$detail$
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
 return jsonb_build_object('kind'
 $detail$);
 execute definition;
end $detail_patch$;
