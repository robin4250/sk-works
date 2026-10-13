alter table private.document_deliveries
  add column if not exists saved_at timestamptz,
  add column if not exists saved_by uuid;

create or replace function private.save_received_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;

  update private.document_deliveries d
  set saved_at=coalesce(d.saved_at,now()),
      saved_by=coalesce(d.saved_by,auth.uid())
  where d.id=p_delivery_id
    and d.recipient_company_id=c;

  if not found then raise exception '受信データを確認できません。'; end if;
end
$$;

create or replace function public.save_received_delivery(p_delivery_id uuid)
returns void
language sql
set search_path=''
as $$ select private.save_received_delivery(p_delivery_id) $$;

revoke all on function public.save_received_delivery(uuid) from public,anon;
grant execute on function public.save_received_delivery(uuid) to authenticated;
