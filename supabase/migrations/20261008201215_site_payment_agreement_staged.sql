-- Staged only. No existing site/settings/certificate records are changed.
create table private.site_payment_agreement_rollout (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
create table private.site_payment_proposals (
 id uuid primary key default gen_random_uuid(),
 shared_item_id uuid not null references private.site_share_inbox(data_item_id),
 revision integer not null check(revision>0),
 proposed_company_id uuid not null references public.companies(id),
 proposed_by uuid not null,
 terms jsonb not null check(jsonb_typeof(terms)='object'),
 created_at timestamptz not null default now(),
 unique(shared_item_id,revision)
);
create table private.site_payment_confirmations (
 proposal_id uuid not null references private.site_payment_proposals(id),
 company_id uuid not null references public.companies(id),
 confirmed_by uuid not null,
 confirmed_at timestamptz not null default now(),
 primary key(proposal_id,company_id)
);
alter table private.site_payment_agreement_rollout enable row level security;
alter table private.site_payment_proposals enable row level security;
alter table private.site_payment_confirmations enable row level security;
revoke all on private.site_payment_agreement_rollout,private.site_payment_proposals,
 private.site_payment_confirmations from public,anon,authenticated;

-- VOLATILE deliberately obtains fresh snapshots when called after lock waits.
create function private.site_payment_pair(p_item uuid,p_company uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare x record; parent_id uuid; child_id uuid;
begin
 if auth.uid() is null or not private.account_access_allowed() or not exists(
  select 1 from public.company_members m where m.company_id=p_company
   and m.user_id=auth.uid() and m.role::text in ('owner','admin')
 ) then raise exception '管理者のみ操作できます。' using errcode='42501'; end if;
 select d.sender_company_id,d.recipient_company_id,
  (i.payload->>'source_site_id')::uuid source_site_id,b.accepted_site_id
 into x from private.site_share_inbox b
 join private.company_data_delivery_items i on i.id=b.data_item_id
 join private.document_deliveries d on d.id=i.delivery_id
 where b.data_item_id=p_item and b.status='accepted' and i.payload_kind='site_share'
  and b.recipient_company_id=d.recipient_company_id
  and p_company in (d.sender_company_id,d.recipient_company_id);
 if x.source_site_id is null or x.accepted_site_id is null then
  raise exception '承認済みの共有現場が必要です。'; end if;
 select c.parent_company_id,c.child_company_id into parent_id,child_id
 from private.company_connections c where c.status='accepted' and
 ((c.parent_company_id=x.sender_company_id and c.child_company_id=x.recipient_company_id)
 or(c.parent_company_id=x.recipient_company_id and c.child_company_id=x.sender_company_id));
 if parent_id is null or not exists(select 1 from public.sites s
  where s.id=x.source_site_id and s.company_id=x.sender_company_id)
 or not exists(select 1 from public.sites s where s.id=x.accepted_site_id
  and s.company_id=x.recipient_company_id) then raise exception '会社・現場の対応が確認できません。'; end if;
 if not exists(select 1 from private.site_payment_agreement_rollout r
  where r.company_id=parent_id and r.enabled) or not exists(
  select 1 from private.site_payment_agreement_rollout r where r.company_id=child_id and r.enabled
 ) then raise exception '現場別支払合意は未有効です。' using errcode='55000'; end if;
 return jsonb_build_object('parent_company_id',parent_id,'child_company_id',child_id,
  'source_site_id',x.source_site_id,'recipient_site_id',x.accepted_site_id);
end $$;

create function private.site_payment_agreement_workspace(p_item uuid,p_company uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare pair jsonb; proposals jsonb; own_billing jsonb;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'revision',p.revision,
  'proposed_company_id',p.proposed_company_id,'terms',p.terms,'created_at',p.created_at,
  'confirmations',(select coalesce(jsonb_agg(jsonb_build_object('company_id',c.company_id,
   'confirmed_at',c.confirmed_at)),'[]'::jsonb) from private.site_payment_confirmations c
   where c.proposal_id=p.id)) order by p.revision desc),'[]'::jsonb)
 into proposals from private.site_payment_proposals p where p.shared_item_id=p_item;
 select jsonb_build_object('billing_square_meter_unit_price_yen',f.billing_square_meter_unit_price_yen,'billing_square_meter_quantity',f.billing_square_meter_quantity,'billing_contract_amount_yen',f.billing_contract_amount_yen,'billing_allowance_1_name',f.billing_allowance_1_name,'billing_allowance_1_amount_yen',f.billing_allowance_1_amount_yen,'billing_allowance_2_name',f.billing_allowance_2_name,'billing_allowance_2_amount_yen',f.billing_allowance_2_amount_yen,'billing_allowance_3_name',f.billing_allowance_3_name,'billing_allowance_3_amount_yen',f.billing_allowance_3_amount_yen) into own_billing from public.site_financial_settings f
 join public.sites s on s.id=f.site_id and s.company_id=p_company
 where s.id in ((pair->>'source_site_id')::uuid,(pair->>'recipient_site_id')::uuid);
 return pair||jsonb_build_object('proposals',proposals,'own_site_billing',own_billing);
end $$;

create function private.site_payment_finite_number(p_value jsonb)
returns numeric language plpgsql immutable set search_path='' as $$
declare result numeric;
begin
 result:=(p_value#>>'{}')::numeric;
 if result::text in ('NaN','Infinity','-Infinity') then raise exception '有限の金額・数量が必要です。'; end if;
 return result;
end $$;
revoke all on function private.site_payment_finite_number(jsonb) from public,anon,authenticated;

create function private.propose_site_payment_terms(p_item uuid,p_company uuid,
 p_expected_revision integer,p_terms jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare pair jsonb; current_revision integer; proposal uuid; amount numeric; base numeric;
 item jsonb; adjustment numeric:=0; mode text; rounding text;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where c.parent_company_id=(pair->>'parent_company_id')::uuid
  and c.child_company_id=(pair->>'child_company_id')::uuid for share;
 -- Serialize both parties on the existing canonical shared-site inbox row.
 perform 1 from private.site_share_inbox where data_item_id=p_item for update;
 pair:=private.site_payment_pair(p_item,p_company);
 select coalesce(max(revision),0) into current_revision from private.site_payment_proposals
 where shared_item_id=p_item;
 if p_expected_revision is null or current_revision<>p_expected_revision then raise exception '最新の提案を再読込してください。' using errcode='40001'; end if;
 if p_terms is null or jsonb_typeof(p_terms)<>'object' then raise exception '金額条件が必要です。'; end if;
 if p_terms::text ~* '"(NaN|[-+]?Infinity)"' then raise exception '有限の金額・数量が必要です。'; end if;
 if (p_terms->>'period_start')::date is null or (p_terms->>'period_end')::date is null
 or (p_terms->>'period_end')::date<(p_terms->>'period_start')::date
 then raise exception '対象期間が必要です。'; end if;
 mode:=p_terms->>'mode'; rounding:=p_terms->>'rounding_rule';
 if mode not in ('square_meter','lump_sum') or mode is null or rounding is null
 or rounding not in ('floor','nearest','ceil') then raise exception '計算方式・端数処理を選択してください。'; end if;
 base:=private.site_payment_finite_number(p_terms->'base_amount_yen');
 if base is null or base<0 or base<>trunc(base) then raise exception '基本額が不正です。'; end if;
 if mode='square_meter' then
  if coalesce(private.site_payment_finite_number(p_terms->'unit_price_yen'),-1)<0 or
   private.site_payment_finite_number(p_terms->'unit_price_yen')<>trunc(private.site_payment_finite_number(p_terms->'unit_price_yen')) or
   coalesce(private.site_payment_finite_number(p_terms->'area'),-1)<0 then raise exception '平米単価と平米数が必要です。'; end if;
  amount:=private.site_payment_finite_number(p_terms->'unit_price_yen')*private.site_payment_finite_number(p_terms->'area');
  amount:=case rounding when 'floor' then floor(amount) when 'ceil' then ceil(amount) else round(amount) end;
  if base<>amount then raise exception '平米計算の総額が一致しません。'; end if;
 end if;
 if jsonb_typeof(p_terms->'adjustments') is distinct from 'array' then raise exception '追加項目が必要です。'; end if;
 for item in select value from jsonb_array_elements(p_terms->'adjustments') loop
  if nullif(trim(item->>'name'),'') is null or item->>'direction' is null or item->>'direction' not in ('addition','deduction')
   or coalesce(private.site_payment_finite_number(item->'amount_yen'),-1)<0
   or private.site_payment_finite_number(item->'amount_yen')<>trunc(private.site_payment_finite_number(item->'amount_yen'))
  then raise exception '追加項目が不正です。'; end if;
  adjustment:=adjustment+private.site_payment_finite_number(item->'amount_yen')*
   case item->>'direction' when 'deduction' then -1 else 1 end;
 end loop;
 if jsonb_typeof(p_terms->'tax_included') is distinct from 'boolean' or
  coalesce(private.site_payment_finite_number(p_terms->'tax_amount_yen'),-1)<0 or
  private.site_payment_finite_number(p_terms->'tax_amount_yen')<>trunc(private.site_payment_finite_number(p_terms->'tax_amount_yen')) or
  coalesce(private.site_payment_finite_number(p_terms->'tax_rate'),-1)<0 or
  coalesce(private.site_payment_finite_number(p_terms->'taxable_amount_yen'),-1)<0 then raise exception '税条件が必要です。'; end if;
 amount:=private.site_payment_finite_number(p_terms->'taxable_amount_yen')*private.site_payment_finite_number(p_terms->'tax_rate')/100;
 amount:=case rounding when 'floor' then floor(amount) when 'ceil' then ceil(amount) else round(amount) end;
 if private.site_payment_finite_number(p_terms->'tax_amount_yen')<>amount and nullif(trim(p_terms->>'tax_override_reason'),'') is null
 then raise exception '税額が税率・課税対象・端数処理と一致しません。手動変更理由が必要です。'; end if;
 amount:=base+adjustment+case when (p_terms->>'tax_included')::boolean then 0
  else private.site_payment_finite_number(p_terms->'tax_amount_yen') end;
 if amount<0 or amount<>coalesce(private.site_payment_finite_number(p_terms->'final_amount_yen'),-1)
 then raise exception '最終額が一致しません。'; end if;
 insert into private.site_payment_proposals(shared_item_id,revision,proposed_company_id,proposed_by,terms)
 values(p_item,current_revision+1,p_company,auth.uid(),p_terms) returning id into proposal;
 return proposal;
end $$;

create function private.confirm_site_payment_terms(p_proposal uuid,p_company uuid)
returns void language plpgsql security definer set search_path='' as $$
declare proposal private.site_payment_proposals; pair jsonb;
begin
 select * into proposal from private.site_payment_proposals where id=p_proposal;
 if proposal.id is null then raise exception '提案が見つかりません。'; end if;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where c.parent_company_id=(pair->>'parent_company_id')::uuid
  and c.child_company_id=(pair->>'child_company_id')::uuid for share;
 perform 1 from private.site_share_inbox where data_item_id=proposal.shared_item_id for update;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 if exists(select 1 from private.site_payment_proposals p where
  p.shared_item_id=proposal.shared_item_id and p.revision>proposal.revision)
 then raise exception '古い提案は確認できません。' using errcode='40001'; end if;
 insert into private.site_payment_confirmations(proposal_id,company_id,confirmed_by)
 values(p_proposal,p_company,auth.uid()) on conflict do nothing;
end $$;

create function public.site_payment_agreement_workspace(p_item uuid,p_company uuid)
returns jsonb language sql set search_path='' as $$ select private.site_payment_agreement_workspace(p_item,p_company) $$;
create function public.propose_site_payment_terms(p_item uuid,p_company uuid,p_expected_revision integer,p_terms jsonb)
returns uuid language sql set search_path='' as $$ select private.propose_site_payment_terms(p_item,p_company,p_expected_revision,p_terms) $$;
create function public.confirm_site_payment_terms(p_proposal uuid,p_company uuid)
returns void language sql set search_path='' as $$ select private.confirm_site_payment_terms(p_proposal,p_company) $$;
revoke all on function private.site_payment_pair(uuid,uuid),
 private.site_payment_agreement_workspace(uuid,uuid),private.propose_site_payment_terms(uuid,uuid,integer,jsonb),
 private.confirm_site_payment_terms(uuid,uuid) from public,anon,authenticated;
revoke all on function public.site_payment_agreement_workspace(uuid,uuid),
 public.propose_site_payment_terms(uuid,uuid,integer,jsonb),public.confirm_site_payment_terms(uuid,uuid) from public,anon;
grant execute on function public.site_payment_agreement_workspace(uuid,uuid),
 public.propose_site_payment_terms(uuid,uuid,integer,jsonb),public.confirm_site_payment_terms(uuid,uuid) to authenticated;
-- Wrappers need execute on internal functions; bodies independently authorize.
grant execute on function private.site_payment_agreement_workspace(uuid,uuid),
 private.propose_site_payment_terms(uuid,uuid,integer,jsonb),private.confirm_site_payment_terms(uuid,uuid) to authenticated;

create function private.site_payment_agreement_targets(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() or not exists(
  select 1 from public.company_members m where m.company_id=p_company
  and m.user_id=auth.uid() and m.role::text in ('owner','admin')
 ) then raise exception '管理者のみ操作できます。' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('shared_item_id',b.data_item_id,
  'site_name',s.name,'counterparty_name',co.name)),'[]'::jsonb) into result
 from private.site_share_inbox b join private.company_data_delivery_items i on i.id=b.data_item_id
 join private.document_deliveries d on d.id=i.delivery_id
 join public.sites s on s.id=(i.payload->>'source_site_id')::uuid and s.company_id=d.sender_company_id
 join public.sites target on target.id=b.accepted_site_id and target.company_id=d.recipient_company_id
 join public.companies co on co.id=case when p_company=d.sender_company_id then d.recipient_company_id else d.sender_company_id end
 where b.status='accepted' and i.payload_kind='site_share'
 and p_company in(d.sender_company_id,d.recipient_company_id)
 and exists(select 1 from private.company_connections c where c.status='accepted'
  and ((c.parent_company_id=d.sender_company_id and c.child_company_id=d.recipient_company_id)
   or(c.parent_company_id=d.recipient_company_id and c.child_company_id=d.sender_company_id)))
 and exists(select 1 from private.site_payment_agreement_rollout r where r.company_id=d.sender_company_id and r.enabled)
 and exists(select 1 from private.site_payment_agreement_rollout r where r.company_id=d.recipient_company_id and r.enabled);
 return result;
end $$;
create function public.site_payment_agreement_targets(p_company uuid)
returns jsonb language sql set search_path='' as $$ select private.site_payment_agreement_targets(p_company) $$;
revoke all on function private.site_payment_agreement_targets(uuid),public.site_payment_agreement_targets(uuid) from public,anon;
grant execute on function private.site_payment_agreement_targets(uuid),public.site_payment_agreement_targets(uuid) to authenticated;

create table private.site_payment_document_snapshots (
 proposal_id uuid primary key references private.site_payment_proposals(id),
 snapshot jsonb not null,
 created_by uuid not null,
 created_at timestamptz not null default now()
);
alter table private.site_payment_document_snapshots enable row level security;
revoke all on private.site_payment_document_snapshots from public,anon,authenticated;
create function private.saved_site_payment_document(p_proposal uuid,p_company uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare proposal private.site_payment_proposals; pair jsonb; result jsonb;
begin
 select * into proposal from private.site_payment_proposals where id=p_proposal;
 if proposal.id is null then raise exception '提案が見つかりません。'; end if;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where c.parent_company_id=(pair->>'parent_company_id')::uuid
  and c.child_company_id=(pair->>'child_company_id')::uuid for share;
 perform 1 from private.site_share_inbox where data_item_id=proposal.shared_item_id for update;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 if exists(select 1 from private.site_payment_proposals p where p.shared_item_id=proposal.shared_item_id
  and p.revision>proposal.revision) then raise exception '最新版を確認してください。' using errcode='40001'; end if;
 if not exists(select 1 from private.site_payment_confirmations c where c.proposal_id=p_proposal
  and c.company_id=(pair->>'parent_company_id')::uuid) or not exists(
  select 1 from private.site_payment_confirmations c where c.proposal_id=p_proposal
  and c.company_id=(pair->>'child_company_id')::uuid) then raise exception '双方の確認が必要です。'; end if;
 select snapshot into result from private.site_payment_document_snapshots where proposal_id=p_proposal;
 if result is null then
  select jsonb_build_object('proposal_id',proposal.id,'revision',proposal.revision,'terms',proposal.terms,
   'parent_company_name',parent.name,'subcontractor_company_name',child.name,'site_name',s.name,
   'parent_company_id',parent.id,'subcontractor_company_id',child.id)
  into result from public.companies parent,public.companies child,public.sites s
  where parent.id=(pair->>'parent_company_id')::uuid and child.id=(pair->>'child_company_id')::uuid
  and s.id=(pair->>'source_site_id')::uuid;
  insert into private.site_payment_document_snapshots(proposal_id,snapshot,created_by)
  values(p_proposal,result,auth.uid());
 end if;
 return result;
end $$;
create function public.saved_site_payment_document(p_proposal uuid,p_company uuid)
returns jsonb language sql set search_path='' as $$ select private.saved_site_payment_document(p_proposal,p_company) $$;
revoke all on function private.saved_site_payment_document(uuid,uuid),public.saved_site_payment_document(uuid,uuid) from public,anon;
grant execute on function private.saved_site_payment_document(uuid,uuid),public.saved_site_payment_document(uuid,uuid) to authenticated;
