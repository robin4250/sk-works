-- Only future sealed-contract events are delivered. No rollout or historical
-- outbox backfill is performed, and no external push/SMS dispatcher is invoked.
create table private.site_contract_notification_receipts (
 outbox_id uuid not null references private.site_contract_notification_outbox(id),
 recipient_user_id uuid not null references auth.users(id) on delete cascade,
 notification_id uuid not null unique references public.app_notifications(id) on delete cascade,
 primary key(outbox_id,recipient_user_id)
);
alter table private.site_contract_notification_receipts enable row level security;
revoke all on private.site_contract_notification_receipts from public,anon,authenticated;

create function private.deliver_site_contract_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare item uuid; sender uuid; recipient uuid; actor_company uuid; r uuid; n uuid;
begin
 select p.shared_item_id,d.sender_company_id,d.recipient_company_id
 into item,sender,recipient from private.site_payment_proposals p
 join private.company_data_delivery_items i on i.id=p.shared_item_id
 join private.document_deliveries d on d.id=i.delivery_id where p.id=new.proposal_id;
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
revoke all on function private.deliver_site_contract_notification() from public,anon,authenticated;
create trigger site_contract_notification_delivery after insert on private.site_contract_notification_outbox
 for each row execute function private.deliver_site_contract_notification();

create function private.get_site_contract_notification_target(p_notification uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare notice public.app_notifications; event private.site_contract_notification_outbox; item uuid;
begin
 if auth.uid() is null or not private.account_access_allowed() then
  raise exception '通知を開く権限がありません。' using errcode='42501'; end if;
 select n.* into notice from public.app_notifications n
 join private.site_contract_notification_receipts r on r.notification_id=n.id and r.recipient_user_id=auth.uid()
 where n.id=p_notification and n.recipient_user_id=auth.uid() and n.action_key='site_payment_agreement';
 if notice.id is null then raise exception '通知を開く権限がありません。' using errcode='42501'; end if;
 select o.* into event from private.site_contract_notification_outbox o
 join private.site_contract_notification_receipts r on r.outbox_id=o.id where r.notification_id=notice.id;
 select shared_item_id into item from private.site_payment_proposals where id=event.proposal_id;
 if event.company_id is distinct from notice.company_id or item is distinct from notice.action_id then
  raise exception '通知の対象を確認できません。' using errcode='42501'; end if;
 perform private.site_payment_pair(item,notice.company_id);
 return jsonb_build_object('company_id',notice.company_id,'shared_item_id',item,
  'proposal_id',event.proposal_id,'event',event.event);
end $$;
revoke all on function private.get_site_contract_notification_target(uuid) from public,anon;
grant execute on function private.get_site_contract_notification_target(uuid) to authenticated;
create function public.get_site_contract_notification_target(p_notification uuid) returns jsonb
language sql set search_path='' as $$ select private.get_site_contract_notification_target(p_notification) $$;
revoke all on function public.get_site_contract_notification_target(uuid) from public,anon;
grant execute on function public.get_site_contract_notification_target(uuid) to authenticated;
