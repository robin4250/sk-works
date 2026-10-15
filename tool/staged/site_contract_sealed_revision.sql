-- STAGED ONLY: not a migration and never applied to the application database.
-- Existing mutually confirmed proposals remain immutable. No payroll writes.
create table private.site_contract_seals (
 proposal_id uuid not null references private.site_payment_proposals(id),
 company_id uuid not null references public.companies(id),
 actor_id uuid not null,
 action text not null check(action in ('sent','approved')),
 seal_snapshot jsonb not null check(jsonb_typeof(seal_snapshot)='object'),
 recorded_at timestamptz not null default now(),
 primary key(proposal_id,company_id)
);
create table private.site_contract_notification_outbox (
 id uuid primary key default gen_random_uuid(),
 proposal_id uuid not null references private.site_payment_proposals(id),
 company_id uuid not null references public.companies(id),
 event text not null check(event in ('terms_sent','terms_approved')),
 payload jsonb not null,
 created_at timestamptz not null default now(),
 unique(proposal_id,company_id,event)
);
alter table private.site_contract_seals enable row level security;
alter table private.site_contract_notification_outbox enable row level security;
revoke all on private.site_contract_seals,private.site_contract_notification_outbox from public,anon,authenticated;

create function private.send_sealed_site_contract(p_item uuid,p_company uuid,
 p_expected_revision integer,p_terms jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare pair jsonb; sender uuid; recipient uuid; proposal uuid; seal jsonb; start_day date;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where
  c.parent_company_id=(pair->>'parent_company_id')::uuid and
  c.child_company_id=(pair->>'child_company_id')::uuid for share;
 -- Hold the canonical pair before proposal creation, capturing the same actor,
 -- connection and rollout authorization used by existing agreement functions.
 perform 1 from private.site_share_inbox where data_item_id=p_item for update;
 pair:=private.site_payment_pair(p_item,p_company);
 select d.sender_company_id,d.recipient_company_id into sender,recipient
 from private.company_data_delivery_items i
 join private.document_deliveries d on d.id=i.delivery_id where i.id=p_item;
 if sender is distinct from p_company then
  raise exception '現場の共有元管理者が押印して送信してください。' using errcode='42501';
 end if;
 start_day:=(p_terms->>'effective_from')::date;
 if start_day is null or start_day<(p_terms->>'period_start')::date
  or start_day>(p_terms->>'period_end')::date then
  raise exception '対象期間内の適用開始日が必要です。';
 end if;
 -- Never accept client-supplied seal or approver identity.
 if p_terms ?| array['company_seal_snapshot','seal_snapshot','approved_by','actor_id'] then
  raise exception '印影・承認者はサーバーで記録します。';
 end if;
 seal:=private.document_company_seal_snapshot(null,p_company,true)->'company_seal_snapshot';
 if seal is null or jsonb_typeof(seal)<>'object' then raise exception '会社角印を設定してください。'; end if;
 proposal:=private.propose_site_payment_terms(p_item,p_company,p_expected_revision,p_terms);
 insert into private.site_contract_seals values(proposal,p_company,auth.uid(),'sent',seal,now());
 perform private.confirm_site_payment_terms(proposal,p_company);
 insert into private.site_contract_notification_outbox(proposal_id,company_id,event,payload)
 select proposal,cid,'terms_sent',jsonb_build_object('action_key','site_payment_agreement',
  'shared_item_id',p_item,'proposal_id',proposal,'company_id',cid,'event','terms_sent')
 from unnest(array[sender,recipient]) cid;
 return proposal;
end $$;

create function private.approve_sealed_site_contract(p_proposal uuid,p_company uuid)
returns void language plpgsql security definer set search_path='' as $$
declare p private.site_payment_proposals; pair jsonb; sender uuid; recipient uuid; seal jsonb;
begin
 select * into p from private.site_payment_proposals where id=p_proposal;
 if p.id is null then raise exception '契約が見つかりません。'; end if;
 pair:=private.site_payment_pair(p.shared_item_id,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where
  c.parent_company_id=(pair->>'parent_company_id')::uuid and
  c.child_company_id=(pair->>'child_company_id')::uuid for share;
 perform 1 from private.site_share_inbox where data_item_id=p.shared_item_id for update;
 pair:=private.site_payment_pair(p.shared_item_id,p_company);
 select d.sender_company_id,d.recipient_company_id into sender,recipient
 from private.company_data_delivery_items i join private.document_deliveries d on d.id=i.delivery_id
 where i.id=p.shared_item_id;
 if recipient is distinct from p_company or not exists(select 1 from private.site_contract_seals
  where proposal_id=p_proposal and company_id=sender and action='sent') then
  raise exception '受信側管理者のみ送信済み注文書を承認できます。' using errcode='42501';
 end if;
 if exists(select 1 from private.site_payment_proposals where shared_item_id=p.shared_item_id
  and revision>p.revision) then raise exception '最新版を確認してください。' using errcode='40001'; end if;
 -- Idempotent approval preserves the original actor, time and seal forever.
 if exists(select 1 from private.site_contract_seals where proposal_id=p_proposal and company_id=p_company)
 then return; end if;
 seal:=private.document_company_seal_snapshot(null,p_company,true)->'company_seal_snapshot';
 if seal is null or jsonb_typeof(seal)<>'object' then raise exception '会社角印を設定してください。'; end if;
 insert into private.site_contract_seals values(p_proposal,p_company,auth.uid(),'approved',seal,now());
 perform private.confirm_site_payment_terms(p_proposal,p_company);
 insert into private.site_contract_notification_outbox(proposal_id,company_id,event,payload)
 select p_proposal,cid,'terms_approved',jsonb_build_object('action_key','site_payment_agreement',
  'shared_item_id',p.shared_item_id,'proposal_id',p_proposal,'company_id',cid,'event','terms_approved')
 from unnest(array[sender,recipient]) cid on conflict do nothing;
end $$;
-- Once this shared site uses sealed contracts, the legacy confirmation RPC
-- cannot approve an unsealed proposal or manufacture the other party's seal.
create function private.guard_site_contract_confirmation() returns trigger
language plpgsql security definer set search_path='' as $$
declare item uuid;
begin
 select shared_item_id into item from private.site_payment_proposals where id=new.proposal_id;
 if exists(select 1 from private.site_contract_seals s join private.site_payment_proposals p
   on p.id=s.proposal_id where p.shared_item_id=item)
 and not exists(select 1 from private.site_contract_seals s where s.proposal_id=new.proposal_id
   and s.company_id=new.company_id and s.actor_id=auth.uid()) then
  raise exception '注文書・注文請書の押印承認画面から操作してください。' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function private.guard_site_contract_confirmation() from public,anon,authenticated;
create trigger site_contract_confirmation_requires_seal before insert on private.site_payment_confirmations
 for each row execute function private.guard_site_contract_confirmation();

create function private.site_contract_workspace(p_item uuid,p_company uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare pair jsonb; proposals jsonb;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'revision',p.revision,'terms',p.terms,
  'confirmations',(select coalesce(jsonb_agg(jsonb_build_object('company_id',s.company_id,
    'confirmed_at',s.recorded_at)),'[]'::jsonb) from private.site_contract_seals s where s.proposal_id=p.id),
  'seals',(select coalesce(jsonb_agg(jsonb_build_object('company_id',s.company_id,'actor_id',s.actor_id,
    'action',s.action,'recorded_at',s.recorded_at,'seal_snapshot',s.seal_snapshot)),'[]'::jsonb)
    from private.site_contract_seals s where s.proposal_id=p.id)) order by p.revision desc),'[]'::jsonb)
 into proposals from private.site_payment_proposals p where p.shared_item_id=p_item;
 return pair||jsonb_build_object('proposals',proposals);
end $$;
revoke all on function private.site_contract_workspace(uuid,uuid) from public,anon,authenticated;
revoke all on function private.send_sealed_site_contract(uuid,uuid,integer,jsonb),
 private.approve_sealed_site_contract(uuid,uuid) from public,anon,authenticated;
create function public.send_sealed_site_contract(p_item uuid,p_company uuid,
 p_expected_revision integer,p_terms jsonb) returns uuid language sql set search_path='' as
 $$select private.send_sealed_site_contract(p_item,p_company,p_expected_revision,p_terms)$$;
create function public.approve_sealed_site_contract(p_proposal uuid,p_company uuid)
returns void language sql set search_path='' as
 $$select private.approve_sealed_site_contract(p_proposal,p_company)$$;
create function public.site_contract_workspace(p_item uuid,p_company uuid)
returns jsonb language sql set search_path='' as
 $$select private.site_contract_workspace(p_item,p_company)$$;
revoke all on function public.send_sealed_site_contract(uuid,uuid,integer,jsonb),
 public.approve_sealed_site_contract(uuid,uuid),public.site_contract_workspace(uuid,uuid) from public,anon;
grant execute on function public.send_sealed_site_contract(uuid,uuid,integer,jsonb),
 public.approve_sealed_site_contract(uuid,uuid),
 private.send_sealed_site_contract(uuid,uuid,integer,jsonb),
 private.approve_sealed_site_contract(uuid,uuid),public.site_contract_workspace(uuid,uuid),
 private.site_contract_workspace(uuid,uuid) to authenticated;
-- Rollout is checked by existing site_payment_pair on every mutation.
-- Remains staged until legacy confirmation entry, PDF and pricing integration
-- have been reviewed together; outbox is not a delivered notification.
