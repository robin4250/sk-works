-- STAGED: canonical contract roles are independent of who shared the site first.
-- No rollout, company link, existing proposal or approval records are changed.
create or replace function private.preview_site_contract_seal(p_item uuid,p_company uuid,p_proposal uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare pair jsonb; seal jsonb; current_revision integer; sender uuid; recipient uuid;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where
  c.parent_company_id=(pair->>'parent_company_id')::uuid and
  c.child_company_id=(pair->>'child_company_id')::uuid for share;
 perform 1 from private.site_share_inbox where data_item_id=p_item for update;
 pair:=private.site_payment_pair(p_item,p_company);
 sender:=(pair->>'parent_company_id')::uuid;
 recipient:=(pair->>'child_company_id')::uuid;
 select coalesce(max(p.revision),0) into current_revision from private.site_payment_proposals p where p.shared_item_id=p_item;
 if p_proposal is null then
  if sender is distinct from p_company then raise exception '発注する親会社の管理者のみ送信できます。' using errcode='42501'; end if;
 elsif recipient is distinct from p_company or not exists(select 1 from private.site_payment_proposals p
  join private.site_contract_seals s on s.proposal_id=p.id and s.company_id=sender and s.action='sent'
  where p.id=p_proposal and p.shared_item_id=p_item and p.revision=current_revision) then
  raise exception '最新版の送信済み契約を受信側で確認してください。' using errcode='40001';
 end if;
 -- The official snapshot helper locks the same company row as seal settings.
 perform 1 from public.companies where id=p_company for share;
 if not exists(select 1 from public.companies where id=p_company and company_seal_enabled) then
  raise exception '会社角印を有効にしてください。' using errcode='55000'; end if;
 seal:=private.document_company_seal_snapshot(null,p_company,true)->'company_seal_snapshot';
 if seal is null or jsonb_typeof(seal)<>'object' or seal='{}'::jsonb then
  raise exception '会社角印を設定してください。'; end if;
 -- Recheck after the company-row lock wait; never reuse a pre-wait capability.
 perform private.site_payment_pair(p_item,p_company);
 return jsonb_build_object('company_id',p_company,'shared_item_id',p_item,
  'proposal_id',p_proposal,'revision',current_revision,'seal_snapshot',seal,
  'atomic_seal_version',1,'rollout_enabled',true,
  'sender_company_id',sender,'recipient_company_id',recipient,
  'can_send',p_proposal is null and p_company=sender,
  'can_approve',p_proposal is not null and p_company=recipient and not exists(
   select 1 from private.site_contract_seals s where s.proposal_id=p_proposal and s.company_id=p_company),
  'seal_hash',encode(sha256(convert_to(seal::text,'UTF8')),'hex'));
end $$;

create or replace function private.send_sealed_site_contract(p_item uuid,p_company uuid,
 p_expected_revision integer,p_terms jsonb,p_expected_seal_hash text) returns uuid
language plpgsql security definer set search_path='' as $$
declare pair jsonb; sender uuid; recipient uuid; proposal uuid; seal jsonb; start_day date; preview jsonb;
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
 sender:=(pair->>'parent_company_id')::uuid;
 recipient:=(pair->>'child_company_id')::uuid;
 if sender is distinct from p_company then
  raise exception '発注する親会社の管理者が押印して送信してください。' using errcode='42501';
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
 preview:=private.preview_site_contract_seal(p_item,p_company,null);
 if p_expected_seal_hash is null or p_expected_seal_hash is distinct from preview->>'seal_hash' then
  raise exception '会社角印が変更されました。プレビューを再確認してください。' using errcode='40001'; end if;
 seal:=preview->'seal_snapshot';
 proposal:=private.propose_site_payment_terms(p_item,p_company,p_expected_revision,p_terms);
 insert into private.site_contract_seals values(proposal,p_company,auth.uid(),'sent',seal,now());
 perform private.confirm_site_payment_terms(proposal,p_company);
 insert into private.site_contract_notification_outbox(proposal_id,company_id,event,payload)
 select proposal,cid,'terms_sent',jsonb_build_object('action_key','site_payment_agreement',
  'shared_item_id',p_item,'proposal_id',proposal,'company_id',cid,'event','terms_sent')
 from unnest(array[sender,recipient]) cid;
 return proposal;
end $$;

create or replace function private.approve_sealed_site_contract(p_proposal uuid,p_company uuid,p_expected_revision integer,p_expected_seal_hash text)
returns void language plpgsql security definer set search_path='' as $$
declare p private.site_payment_proposals; pair jsonb; sender uuid; recipient uuid; seal jsonb; preview jsonb;
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
 sender:=(pair->>'parent_company_id')::uuid;
 recipient:=(pair->>'child_company_id')::uuid;
 if recipient is distinct from p_company or not exists(select 1 from private.site_contract_seals
  where proposal_id=p_proposal and company_id=sender and action='sent') then
  raise exception '受信側管理者のみ送信済み注文書を承認できます。' using errcode='42501';
 end if;
 if exists(select 1 from private.site_payment_proposals where shared_item_id=p.shared_item_id
  and revision>p.revision) then raise exception '最新版を確認してください。' using errcode='40001'; end if;
 if p_expected_revision is null or p_expected_revision<>p.revision then
  raise exception '最新版を確認してください。' using errcode='40001'; end if;
 -- Idempotent approval preserves the original actor, time and seal forever.
 select s.seal_snapshot into seal from private.site_contract_seals s
 where s.proposal_id=p_proposal and s.company_id=p_company;
 if found then
  if p_expected_seal_hash is null or p_expected_seal_hash is distinct from
   encode(sha256(convert_to(seal::text,'UTF8')),'hex') then
   raise exception '保存済みの押印内容を再確認してください。' using errcode='40001'; end if;
  return;
 end if;
 preview:=private.preview_site_contract_seal(p.shared_item_id,p_company,p_proposal);
 if p_expected_seal_hash is null or p_expected_seal_hash is distinct from preview->>'seal_hash' then
  raise exception '会社角印が変更されました。プレビューを再確認してください。' using errcode='40001'; end if;
 seal:=preview->'seal_snapshot';
 insert into private.site_contract_seals values(p_proposal,p_company,auth.uid(),'approved',seal,now());
 perform private.confirm_site_payment_terms(p_proposal,p_company);
 insert into private.site_contract_notification_outbox(proposal_id,company_id,event,payload)
 select p_proposal,cid,'terms_approved',jsonb_build_object('action_key','site_payment_agreement',
  'shared_item_id',p.shared_item_id,'proposal_id',p_proposal,'company_id',cid,'event','terms_approved')
 from unnest(array[sender,recipient]) cid on conflict do nothing;
end $$;

create or replace function private.site_contract_workspace(p_item uuid,p_company uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare pair jsonb; proposals jsonb; sender uuid; recipient uuid; latest uuid;
begin
 pair:=private.site_payment_pair(p_item,p_company);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'revision',p.revision,'terms',p.terms,
  'confirmations',(select coalesce(jsonb_agg(jsonb_build_object('company_id',s.company_id,
    'confirmed_at',s.recorded_at)),'[]'::jsonb) from private.site_contract_seals s where s.proposal_id=p.id),
  'seals',(select coalesce(jsonb_agg(jsonb_build_object('company_id',s.company_id,'actor_id',s.actor_id,
    'action',s.action,'recorded_at',s.recorded_at,'seal_snapshot',s.seal_snapshot)),'[]'::jsonb)
    from private.site_contract_seals s where s.proposal_id=p.id)) order by p.revision desc),'[]'::jsonb)
 into proposals from private.site_payment_proposals p where p.shared_item_id=p_item;
 sender:=(pair->>'parent_company_id')::uuid;
 recipient:=(pair->>'child_company_id')::uuid;
 select p.id into latest from private.site_payment_proposals p
 where p.shared_item_id=p_item order by p.revision desc limit 1;
 -- Hints describe existing authority, never grant it. Mutations recheck every
 -- boundary and exact preview snapshot; older backends omit this version.
 return pair||jsonb_build_object('proposals',proposals,'atomic_seal_version',1,
  'rollout_enabled',true,'sender_company_id',sender,'recipient_company_id',recipient,
  'can_send',p_company=sender,'can_approve',p_company=recipient and exists(
   select 1 from private.site_contract_seals s where s.proposal_id=latest
    and s.company_id=sender and s.action='sent') and not exists(
   select 1 from private.site_contract_seals s where s.proposal_id=latest and s.company_id=p_company));
end $$;

create or replace function private.deliver_site_contract_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare item uuid; sender uuid; recipient uuid; actor_company uuid; r uuid; n uuid;
begin
 select p.shared_item_id,d.sender_company_id,d.recipient_company_id
 into item,sender,recipient from private.site_payment_proposals p
 join private.company_data_delivery_items i on i.id=p.shared_item_id
 join private.document_deliveries d on d.id=i.delivery_id where p.id=new.proposal_id;
 -- The sharing direction is not the ordering direction.
 select c.parent_company_id,c.child_company_id into sender,recipient
 from private.company_connections c where c.status='accepted'
 and ((c.parent_company_id=sender and c.child_company_id=recipient)
   or (c.parent_company_id=recipient and c.child_company_id=sender));
 actor_company:=case new.event when 'terms_sent' then sender when 'terms_approved' then recipient end;
 if item is null or new.company_id not in(sender,recipient) or actor_company is null
 or not exists(select 1 from private.site_contract_seals s where s.proposal_id=new.proposal_id
  and s.company_id=actor_company and s.actor_id=auth.uid()
  and s.action=case new.event when 'terms_sent' then 'sent' else 'approved' end)
 then raise exception '契約通知の保存根拠を確認できません。' using errcode='42501'; end if;
 -- The acting party must still be authorized; pair checks account, membership,
 -- accepted sharing/connection and both existing rollout flags. Never trust payload.
 perform private.site_payment_pair(item,actor_company);
 for r in select distinct m.user_id from public.company_members m
  where m.company_id=new.company_id and m.role::text in('owner','admin') order by m.user_id
 loop
  if not exists(select 1 from private.site_contract_notification_receipts
   where outbox_id=new.id and recipient_user_id=r) then
   n:=private.enqueue_notification(new.company_id,r,'site_payment_agreement',
    case new.event when 'terms_sent' then '現場契約が押印して送信されました' else '現場契約が双方押印で承認されました' end,
    '対象の現場と契約内容を確認してください。','site_payment_agreement',item);
   insert into private.site_contract_notification_receipts values(new.id,r,n);
  end if;
 end loop;
 return new;
end $$;
