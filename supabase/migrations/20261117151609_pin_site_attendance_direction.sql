begin;

-- A company connection permits a direction. Each accepted site mapping
-- records which permitted direction it actually uses for attendance.
alter table private.site_share_inbox
  add column attendance_child_company_id uuid references public.companies(id);

create function private.unambiguous_site_attendance_child(p_item uuid)
returns uuid language sql stable set search_path = ''
as $$
  select (array_agg(distinct connection.child_company_id))[1]
  from private.company_data_delivery_items item
  join private.document_deliveries delivery on delivery.id=item.delivery_id
  join private.company_connections connection on connection.status='accepted'
    and ((connection.child_company_id=delivery.sender_company_id
          and connection.parent_company_id=delivery.recipient_company_id)
      or (connection.child_company_id=delivery.recipient_company_id
          and connection.parent_company_id=delivery.sender_company_id))
  where item.id=p_item and item.payload_kind='site_share'
  having count(distinct connection.child_company_id)=1;
$$;
revoke all on function private.unambiguous_site_attendance_child(uuid)
  from public, anon, authenticated;

-- Preserve the established direction even when the company link is suspended.
-- An existing grant still needs an active company link to expose attendance.
update private.site_share_inbox inbox
set attendance_child_company_id=grant_row.child_company_id
from private.site_share_attendance_grants grant_row
join private.company_data_delivery_items item on item.id=grant_row.data_item_id
join private.document_deliveries delivery on delivery.id=item.delivery_id
where inbox.data_item_id=grant_row.data_item_id
  and inbox.status='accepted' and item.payload_kind='site_share'
  and inbox.recipient_company_id=delivery.recipient_company_id
  and grant_row.child_company_id in (delivery.sender_company_id, delivery.recipient_company_id);

update private.site_share_inbox inbox
set attendance_child_company_id=private.unambiguous_site_attendance_child(inbox.data_item_id)
where inbox.status='accepted' and inbox.attendance_child_company_id is null;

create function private.pin_accepted_site_attendance_direction()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  source_site text;
begin
  if tg_op='INSERT' and new.status='pending' then
    select item.payload->>'source_site_id' into source_site
    from private.company_data_delivery_items item
    where item.id=new.data_item_id and item.payload_kind='site_share';
    if source_site is not null then
      perform pg_advisory_xact_lock(hashtextextended(source_site||':'||new.recipient_company_id::text,0));
      if exists(
        select 1 from private.site_share_inbox previous
        join private.company_data_delivery_items item on item.id=previous.data_item_id
        where previous.recipient_company_id=new.recipient_company_id
          and previous.status in ('pending','accepted')
          and item.payload_kind='site_share'
          and item.payload->>'source_site_id'=source_site
      ) then raise exception 'この会社には同じ現場をすでに共有しています。' using errcode='55000'; end if;
    end if;
  end if;
  if new.status='accepted' and new.attendance_child_company_id is null
    and not exists(select 1 from private.site_attendance_direction_requests
      where item_id=new.data_item_id) then
    if tg_op='INSERT' then
      new.attendance_child_company_id:=private.unambiguous_site_attendance_child(new.data_item_id);
    elsif old.status is distinct from new.status then
      new.attendance_child_company_id:=private.unambiguous_site_attendance_child(new.data_item_id);
    end if;
  end if;
  if tg_op='UPDATE' then
    if old.attendance_child_company_id is distinct from new.attendance_child_company_id then
      delete from private.site_share_attendance_grants
      where data_item_id=old.data_item_id;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.pin_accepted_site_attendance_direction()
  from public, anon, authenticated;
create trigger pin_accepted_site_attendance_direction
before insert or update of status, attendance_child_company_id on private.site_share_inbox
for each row execute function private.pin_accepted_site_attendance_direction();

create or replace function private.upstream_shared_site_attendance_ids(
  p_company_id uuid,
  p_month date
)
returns table (attendance_id uuid)
language sql
stable
set search_path = ''
as $$
  with recursive mappings as (
    select
      sender.id as sender_site_id,
      sender.company_id as sender_company_id,
      recipient.id as recipient_site_id,
      recipient.company_id as recipient_company_id,
      grant_row.child_company_id as granting_company_id,
      grant_row.first_work_date
    from private.site_share_attendance_grants grant_row
    join private.site_share_inbox inbox
      on inbox.data_item_id = grant_row.data_item_id
    join private.company_data_delivery_items item on item.id = inbox.data_item_id
    join private.document_deliveries delivery on delivery.id = item.delivery_id
    join public.sites sender
      on sender.company_id = delivery.sender_company_id
      and sender.id::text = item.payload->>'source_site_id'
    join public.sites recipient
      on recipient.id = inbox.accepted_site_id
      and recipient.company_id = inbox.recipient_company_id
      and recipient.company_id = delivery.recipient_company_id
    where inbox.status = 'accepted' and item.payload_kind = 'site_share'
      and inbox.attendance_child_company_id = grant_row.child_company_id
  ), hops as (
    select
      case when c.child_company_id = m.sender_company_id
        then m.sender_site_id else m.recipient_site_id end as child_site_id,
      case when c.parent_company_id = m.sender_company_id
        then m.sender_site_id else m.recipient_site_id end as parent_site_id,
      c.child_company_id,
      c.parent_company_id,
      greatest(m.first_work_date, c.link_start_month) as first_work_date
    from mappings m
    join private.company_connections c on c.status = 'accepted'
      and c.child_company_id = m.granting_company_id and (
      (c.parent_company_id = m.recipient_company_id and c.child_company_id = m.sender_company_id)
      or (c.parent_company_id = m.sender_company_id and c.child_company_id = m.recipient_company_id)
    )
  ), sources as (
    select child_site_id, child_company_id, first_work_date,
      array[parent_company_id, child_company_id] as company_path
    from hops
    where parent_company_id = p_company_id
    union
    select h.child_site_id, h.child_company_id,
      greatest(s.first_work_date, h.first_work_date),
      s.company_path || h.child_company_id
    from sources s
    join hops h on h.parent_site_id = s.child_site_id
      and h.parent_company_id = s.child_company_id
    where not h.child_company_id = any(s.company_path)
  )
  select distinct a.id
  from sources s
  join public.attendance_entries a on a.company_id = s.child_company_id
    and a.site_id = s.child_site_id
  where p_month = date_trunc('month', p_month)::date
    and a.work_date >= greatest(p_month, s.first_work_date)
    and a.work_date < p_month + interval '1 month';
$$;

revoke all on function private.upstream_shared_site_attendance_ids(uuid,date)
  from public, anon, authenticated;

create or replace function private.manage_site_attendance_sharing(
  p_item uuid default null, p_start date default null, p_disable boolean default false
)
returns table(item_id uuid, site_name text, parent_name text, first_work_date date)
language plpgsql security definer set search_path = ''
as $$
declare
  company uuid := private.attendance_sharing_company(true);
begin
  if company is null then raise exception 'Attendance sharing requires a company administrator' using errcode='42501'; end if;
  if p_item is not null then
    -- Serialize against any future explicit change of the mapping direction.
    perform 1 from private.site_share_inbox i where i.data_item_id=p_item for update;
    if not exists (
      select 1 from private.manage_site_attendance_sharing() s where s.item_id=p_item
    ) then raise exception 'Shared site not available' using errcode='42501'; end if;
    if p_disable then
      delete from private.site_share_attendance_grants g where g.data_item_id=p_item and g.child_company_id=company;
    elsif p_start is not null then
      insert into private.site_share_attendance_grants(data_item_id,child_company_id,first_work_date)
      values(p_item,company,p_start)
      on conflict(data_item_id) do update set first_work_date=excluded.first_work_date
      where site_share_attendance_grants.child_company_id=excluded.child_company_id;
      if not found then raise exception 'Sharing direction conflict' using errcode='42501'; end if;
    else
      raise exception 'Sharing start date is required' using errcode='22023';
    end if;
  end if;
  return query
    select i.data_item_id, child_site.name, parent_company.name, g.first_work_date
    from private.site_share_inbox i
    join private.company_data_delivery_items item on item.id=i.data_item_id and item.payload_kind='site_share'
    join private.document_deliveries d on d.id=item.delivery_id and d.recipient_company_id=i.recipient_company_id
    join private.company_connections c on c.child_company_id=company and c.status='accepted'
      and ((d.sender_company_id=company and d.recipient_company_id=c.parent_company_id)
        or (d.recipient_company_id=company and d.sender_company_id=c.parent_company_id))
    join public.companies parent_company on parent_company.id=c.parent_company_id
    join public.sites sender on sender.company_id=d.sender_company_id and sender.id::text=item.payload->>'source_site_id'
    join public.sites recipient on recipient.id=i.accepted_site_id and recipient.company_id=d.recipient_company_id
    join public.sites child_site on child_site.id=case when sender.company_id=company then sender.id else recipient.id end
    left join private.site_share_attendance_grants g on g.data_item_id=i.data_item_id and g.child_company_id=company
    where i.status='accepted' and i.attendance_child_company_id=company
    order by parent_company.name,child_site.name,i.data_item_id;
end;
$$;

alter table public.trade_companies add column site_default_role text
  check(site_default_role in ('customer','subcontractor','unset'));

create function private.trade_company_site_default(p_trade_company uuid, p_role text)
returns text language plpgsql security definer set search_path = ''
as $$
declare company uuid := private.attendance_sharing_company(true);
  chosen text;
begin
  if company is null then raise exception '会社情報の管理権限を確認してください。' using errcode='42501'; end if;
  if p_role is not null then
    if p_role not in ('customer','subcontractor','unset') then
      raise exception '役割を確認してください。' using errcode='22023';
    end if;
    update public.trade_companies set site_default_role=p_role
    where id=p_trade_company and company_id=company;
    if not found then raise exception '対象の会社情報を確認してください。' using errcode='42501'; end if;
  end if;
  select coalesce(site_default_role,case when trade_role in ('customer','subcontractor')
    then trade_role else 'unset' end) into chosen from public.trade_companies
  where id=p_trade_company and company_id=company;
  if not found then raise exception '対象の会社情報を確認してください。' using errcode='42501'; end if;
  return chosen;
end;
$$;

create function public.trade_company_site_default(p_trade_company uuid, p_role text default null)
returns text language sql set search_path = ''
as $$ select private.trade_company_site_default(p_trade_company,p_role); $$;
revoke all on function private.trade_company_site_default(uuid,text),
  public.trade_company_site_default(uuid,text) from public, anon;
grant execute on function private.trade_company_site_default(uuid,text),
  public.trade_company_site_default(uuid,text) to authenticated;

create table private.site_attendance_direction_requests (
  item_id uuid primary key references private.site_share_inbox(data_item_id) on delete cascade,
  request_id uuid not null unique default gen_random_uuid(),
  requester_company_id uuid not null references public.companies(id),
  proposed_child_company_id uuid not null references public.companies(id)
);
alter table private.site_attendance_direction_requests enable row level security;
revoke all on private.site_attendance_direction_requests from public, anon, authenticated;

create function private.site_attendance_direction_workspace(
  p_site uuid, p_item uuid, p_action text, p_request uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  company uuid := private.attendance_sharing_company(true);
  other_company uuid;
  current_child uuid;
  proposed_child uuid;
  source_site uuid;
  source_recipient uuid;
  request_row private.site_attendance_direction_requests%rowtype;
  result jsonb;
begin
  if company is null or not exists(
    select 1 from public.sites site where site.id=p_site and site.company_id=company
  ) then raise exception '現場の管理権限を確認してください。' using errcode='42501'; end if;

  if p_action is not null then
    select case when delivery.sender_company_id=company
                  then delivery.recipient_company_id else delivery.sender_company_id end,
           inbox.attendance_child_company_id, sender.id, delivery.recipient_company_id
      into other_company, current_child, source_site, source_recipient
    from private.site_share_inbox inbox
    join private.company_data_delivery_items item on item.id=inbox.data_item_id and item.payload_kind='site_share'
    join private.document_deliveries delivery on delivery.id=item.delivery_id
      and delivery.recipient_company_id=inbox.recipient_company_id
    join public.sites sender on sender.id::text=item.payload->>'source_site_id'
      and sender.company_id=delivery.sender_company_id
    left join public.sites recipient on recipient.id=inbox.accepted_site_id
      and recipient.company_id=delivery.recipient_company_id
    where inbox.data_item_id=p_item
      and ((inbox.status='accepted' and recipient.id is not null
        and ((sender.id=p_site and sender.company_id=company)
          or (recipient.id=p_site and recipient.company_id=company)))
        or (inbox.status='pending' and sender.id=p_site and sender.company_id=company
          and p_action in ('send','receive','cancel')))
    for update of inbox;
    if not found then raise exception '承認済みの共有現場を確認してください。' using errcode='42501'; end if;

    if p_action in ('send','receive','approve') and exists (
      select 1 from private.site_share_inbox previous
      join private.company_data_delivery_items item on item.id=previous.data_item_id
      where previous.recipient_company_id=source_recipient
        and previous.data_item_id<>p_item and previous.status in ('pending','accepted')
        and item.payload_kind='site_share' and item.payload->>'source_site_id'=source_site::text
    ) then raise exception '同じ現場の共有が複数あります。共有先を確認してください。' using errcode='55000'; end if;

    select * into request_row from private.site_attendance_direction_requests
      where item_id=p_item;
    if p_action in ('send','receive') then
      if request_row.request_id is not null then
        raise exception 'この現場には承認待ちの申請があります。' using errcode='55000';
      end if;
      proposed_child:=case when p_action='send' then company else other_company end;
      if current_child is not distinct from proposed_child then
        raise exception '選んだ方向は設定済みです。' using errcode='22023';
      end if;
    elsif p_action in ('approve','reject','cancel') then
      if p_request is null or request_row.request_id is distinct from p_request
        or (p_action='cancel' and request_row.requester_company_id<>company)
        or (p_action<>'cancel' and request_row.requester_company_id<>other_company)
        then raise exception 'この申請を操作できません。' using errcode='42501';
      end if;
      proposed_child:=request_row.proposed_child_company_id;
    else
      raise exception '操作を確認してください。' using errcode='22023';
    end if;

    if p_action in ('send','receive','approve') then
      perform 1 from private.company_connections connection
      where connection.child_company_id=proposed_child
        and connection.parent_company_id=case when proposed_child=company then other_company else company end
        and connection.status='accepted'
      for share;
      if not found then raise exception 'この方向の会社間連携が承認されていません。' using errcode='42501'; end if;
    end if;

    if p_action in ('send','receive') then
      insert into private.site_attendance_direction_requests(item_id, requester_company_id, proposed_child_company_id)
      values(p_item,company,proposed_child);
    else
      if p_action='approve' then
        update private.site_share_inbox set attendance_child_company_id=proposed_child
        where data_item_id=p_item;
      end if;
      delete from private.site_attendance_direction_requests where item_id=p_item;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'item_id',inbox.data_item_id,'company_name',other.name,'site_share_status',inbox.status,
    'other_site',case when sender.company_id=company then recipient.name else sender.name end,
    'default_role',directory.default_role,'trade_company_id',directory.id,
    'direction',case when inbox.attendance_child_company_id=company then 'send'
                     when inbox.attendance_child_company_id=other.id then 'receive' end,
    'can_send',exists(select 1 from private.company_connections link
      where link.child_company_id=company and link.parent_company_id=other.id and link.status='accepted'),
    'can_receive',exists(select 1 from private.company_connections link
      where link.child_company_id=other.id and link.parent_company_id=company and link.status='accepted'),
    'request_id',request.request_id,
    'requested_direction',case when request.proposed_child_company_id=company then 'send'
                               when request.proposed_child_company_id=other.id then 'receive' end,
    'requested_by_us',request.requester_company_id=company
  ) order by other.name,inbox.data_item_id),'[]'::jsonb)
  into result
  from private.site_share_inbox inbox
  join private.company_data_delivery_items item on item.id=inbox.data_item_id and item.payload_kind='site_share'
  join private.document_deliveries delivery on delivery.id=item.delivery_id
    and delivery.recipient_company_id=inbox.recipient_company_id
  join public.sites sender on sender.id::text=item.payload->>'source_site_id' and sender.company_id=delivery.sender_company_id
  left join public.sites recipient on recipient.id=inbox.accepted_site_id and recipient.company_id=delivery.recipient_company_id
  join public.companies other on other.id=case when sender.company_id=company then delivery.recipient_company_id else sender.company_id end
  left join lateral (
    select min(contact.id::text)::uuid as id,
      min(coalesce(contact.site_default_role,case when contact.trade_role in ('customer','subcontractor')
      then contact.trade_role else 'unset' end)) as default_role
    from public.trade_companies contact
    where contact.company_id=company and contact.linked_company_id=other.id
    having count(*)=1
  ) directory on true
  left join private.site_attendance_direction_requests request on request.item_id=inbox.data_item_id
  where (inbox.status='accepted' and recipient.id is not null
    and ((sender.id=p_site and sender.company_id=company)
      or (recipient.id=p_site and recipient.company_id=company)))
    or (inbox.status='pending' and sender.id=p_site and sender.company_id=company);
  return result;
end;
$$;

create function public.site_attendance_direction_workspace(
  p_site uuid, p_item uuid default null, p_action text default null, p_request uuid default null
) returns jsonb language sql set search_path = ''
as $$ select private.site_attendance_direction_workspace(p_site,p_item,p_action,p_request); $$;
revoke all on function private.site_attendance_direction_workspace(uuid,uuid,text,uuid),
  public.site_attendance_direction_workspace(uuid,uuid,text,uuid) from public, anon;
grant execute on function private.site_attendance_direction_workspace(uuid,uuid,text,uuid),
  public.site_attendance_direction_workspace(uuid,uuid,text,uuid) to authenticated;

-- Keep existing directory records and match future synchronization by identity.
create or replace function private.sync_trade_company_directory()
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  cid uuid;
  r record;
  existing_id uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  perform pg_advisory_xact_lock(hashtextextended(cid::text,0));

  for r in
    select c.id,c.name,c.billing_address
    from public.customers c
    where c.company_id=cid
      and c.notes is distinct from 'sko_system_unassigned_invoice_customer'
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and tc.customer_id=r.id
    order by tc.created_at,tc.id
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,address,trade_role,customer_id,created_by,updated_by
      )
      values(cid,r.name,r.billing_address,'customer',r.id,auth.uid(),auth.uid());
    else
      update public.trade_companies
      set customer_id=coalesce(customer_id,r.id),
          trade_role=case when trade_role='subcontractor' then 'both' else trade_role end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;

  for r in
    select p.id,p.name,p.postal_code,p.address,p.phone,p.email
    from public.partner_companies p
    where p.company_id=cid
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and tc.partner_company_id=r.id
    order by tc.created_at,tc.id
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,postal_code,address,phone,email,trade_role,
        partner_company_id,created_by,updated_by
      )
      values(
        cid,r.name,r.postal_code,r.address,r.phone,r.email,'subcontractor',
        r.id,auth.uid(),auth.uid()
      );
    else
      update public.trade_companies
      set partner_company_id=coalesce(partner_company_id,r.id),
          postal_code=coalesce(nullif(postal_code,''),r.postal_code),
          address=coalesce(nullif(address,''),r.address),
          phone=coalesce(nullif(phone,''),r.phone),
          email=coalesce(nullif(email,''),r.email),
          trade_role=case when trade_role='customer' then 'both' else trade_role end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;

  for r in
    select cc.parent_company_id as linked_id,co.name,co.postal_code,co.address,
           co.phone,co.email,co.corporate_number,'customer'::text as role_name
    from private.company_connections cc
    join public.companies co on co.id=cc.parent_company_id
    where cc.child_company_id=cid and cc.status='accepted'
    union all
    select cc.child_company_id as linked_id,co.name,co.postal_code,co.address,
           co.phone,co.email,co.corporate_number,'subcontractor'::text as role_name
    from private.company_connections cc
    join public.companies co on co.id=cc.child_company_id
    where cc.parent_company_id=cid and cc.status='accepted'
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and tc.linked_company_id=r.linked_id
    order by tc.created_at,tc.id
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,postal_code,address,phone,email,corporate_number,
        trade_role,linked_company_id,link_status,created_by,updated_by
      )
      values(
        cid,r.name,r.postal_code,r.address,r.phone,r.email,r.corporate_number,
        r.role_name,r.linked_id,'linked',auth.uid(),auth.uid()
      );
    else
      update public.trade_companies
      set linked_company_id=r.linked_id,
          link_status='linked',
          postal_code=coalesce(nullif(postal_code,''),r.postal_code),
          address=coalesce(nullif(address,''),r.address),
          phone=coalesce(nullif(phone,''),r.phone),
          email=coalesce(nullif(email,''),r.email),
          corporate_number=coalesce(nullif(corporate_number,''),r.corporate_number),
          trade_role=case
            when trade_role<>r.role_name and trade_role<>'both' then 'both'
            else trade_role
          end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;
end
$$;

revoke all on function private.sync_trade_company_directory() from public, anon, authenticated;

-- New role records are created only when this company has no saved role reference.
create or replace function private.ensure_trade_company_legacy_links(p_trade_company_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  tc public.trade_companies%rowtype;
  cid uuid;
  legacy_customer uuid;
  legacy_partner uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;
  select * into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid
  for update;
  if tc.id is null then raise exception '取引会社が見つかりません。'; end if;

  if tc.trade_role in ('customer','both') then
    legacy_customer:=tc.customer_id;
    if legacy_customer is null then
      insert into public.customers(company_id,name,billing_name,billing_address)
      values(cid,tc.name,tc.name,tc.address)
      returning id into legacy_customer;
    end if;
  end if;

  if tc.trade_role in ('subcontractor','both') then
    legacy_partner:=tc.partner_company_id;
    if legacy_partner is null then
      insert into public.partner_companies(
        company_id,name,phone,email,address,postal_code,trade_role,status
      )
      values(cid,tc.name,tc.phone,tc.email,tc.address,tc.postal_code,'subcontractor','active')
      returning id into legacy_partner;
    end if;
  end if;

  update public.trade_companies
  set customer_id=coalesce(legacy_customer,customer_id),
      partner_company_id=coalesce(legacy_partner,partner_company_id),
      updated_by=auth.uid(),
      updated_at=now()
  where id=tc.id;
end
$$;

revoke all on function private.ensure_trade_company_legacy_links(uuid) from public, anon, authenticated;

-- Only a current owner or administrator may approve a company relationship.
create or replace function private.trade_link_company_admin_id() returns uuid
language sql stable security definer set search_path='' as $$
  select member.company_id
  from public.company_members member
  where member.user_id=auth.uid()
    and private.account_access_allowed()
    and member.employment_ended_at is null
    and member.role::text in ('owner','admin')
  order by member.company_id
  limit 1;
$$;
revoke all on function private.trade_link_company_admin_id() from public, anon, authenticated;

-- An approved link may add a role, but never adopt an unrelated same-name role record.
create or replace function private.attach_approved_trade_link(p_owner uuid,p_other uuid,p_role text) returns void language plpgsql security definer set search_path='' as $$
declare target public.companies%rowtype; tid uuid; n integer; legacy_id uuid; tc public.trade_companies%rowtype;
begin
 select * into strict target from public.companies where id=p_other;
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
 select count(*),min(id::text)::uuid into n,tid from public.trade_companies where company_id=p_owner and linked_company_id=p_other;
 if n>1 then raise exception '連携済み会社の重複を確認してください'; end if;
 if tid is null and nullif(trim(target.corporate_number),'') is not null then
  select count(*),min(id::text)::uuid into n,tid from public.trade_companies
   where company_id=p_owner and linked_company_id is null and corporate_number=target.corporate_number;
  if n>1 then raise exception '同じ法人番号の会社が複数あります。整理後に再承認してください'; end if;
 end if;
 if tid is null then
  if exists(select 1 from public.trade_companies where company_id=p_owner and linked_company_id is null
    and lower(trim(name))=lower(trim(target.name))) then
   raise exception '同名の登録済み会社があります。法人番号を確認・登録してから再承認してください';
  end if;
  insert into public.trade_companies(company_id,name,address,phone,corporate_number,trade_role,linked_company_id,link_status,created_by,updated_by)
  values(p_owner,target.name,target.address,target.phone,target.corporate_number,p_role,p_other,'linked',auth.uid(),auth.uid()) returning id into tid;
 else
  update public.trade_companies set trade_role=case when trade_role=p_role then p_role else 'both' end,
   linked_company_id=p_other,link_status='linked',updated_by=auth.uid(),updated_at=now() where id=tid;
 end if;
 select * into strict tc from public.trade_companies where id=tid and company_id=p_owner;
 if p_role='customer' and tc.customer_id is null then
  insert into public.customers(company_id,name,billing_name,billing_address)
  values(p_owner,tc.name,tc.name,tc.address) returning id into legacy_id;
  update public.trade_companies set customer_id=legacy_id where id=tid and company_id=p_owner;
 elsif p_role='subcontractor' and tc.partner_company_id is null then
  insert into public.partner_companies(company_id,name,phone,email,address,postal_code,trade_role,status)
  values(p_owner,tc.name,tc.phone,tc.email,tc.address,tc.postal_code,'subcontractor','active')
  returning id into legacy_id;
  update public.trade_companies set partner_company_id=legacy_id where id=tid and company_id=p_owner;
 end if;
end $$;
revoke all on function private.attach_approved_trade_link(uuid,uuid,text) from public, anon, authenticated;

commit;
