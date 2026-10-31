-- Verbatim deployed function metadata-only READ ONLY capture 2026-10-30.
CREATE OR REPLACE FUNCTION private.respond_site_share(p_data_item_id uuid, p_accept boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c uuid;
  item record;
  payload jsonb;
  new_site uuid;
  customer_id uuid;
  customer_name text;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid()
    and m.role::text in ('owner','admin','manager')
  limit 1;
  if c is null then raise exception '管理者・サブ管理者だけが承認できます。'; end if;

  select s.*,i.payload
  into item
  from private.site_share_inbox s
  join private.company_data_delivery_items i on i.id=s.data_item_id
  where s.data_item_id=p_data_item_id
    and s.recipient_company_id=c
  for update;

  if item.data_item_id is null then raise exception '受信した現場データが見つかりません。'; end if;
  if item.status<>'pending' then raise exception 'この現場データは処理済みです。'; end if;

  if not p_accept then
    update private.site_share_inbox
    set status='rejected',responded_by=auth.uid(),responded_at=now()
    where data_item_id=p_data_item_id;
    return null;
  end if;

  payload:=item.payload;
  customer_name:=nullif(trim(coalesce(payload->>'customer_name','')),'');
  if customer_name is not null then
    select id into customer_id
    from public.customers
    where company_id=c
      and (name=customer_name or billing_name=customer_name)
    order by created_at
    limit 1;

    if customer_id is null then
      insert into public.customers(
        company_id,name,billing_name
      )
      values(c,customer_name,customer_name)
      returning id into customer_id;
    end if;
  end if;

  insert into public.sites(
    company_id,
    customer_id,
    name,
    formal_name,
    address,
    nearest_station,
    representative_name,
    representative_phone,
    notes,
    status,
    latitude,
    longitude,
    created_by,
    updated_at
  )
  values(
    c,
    customer_id,
    coalesce(nullif(payload->>'name',''),'受信現場'),
    nullif(payload->>'formal_name',''),
    nullif(payload->>'address',''),
    nullif(payload->>'nearest_station',''),
    nullif(payload->>'representative_name',''),
    nullif(payload->>'representative_phone',''),
    nullif(payload->>'notes',''),
    'preparation',
    nullif(payload->>'latitude','')::double precision,
    nullif(payload->>'longitude','')::double precision,
    auth.uid(),
    now()
  )
  returning id into new_site;

  update private.site_share_inbox
  set status='accepted',
      responded_by=auth.uid(),
      responded_at=now(),
      accepted_site_id=new_site
  where data_item_id=p_data_item_id;

  update public.app_notifications
  set read_at=coalesce(read_at,now())
  where company_id=c
    and action_key='site_share_approval'
    and action_id=p_data_item_id
    and read_at is null;

  return new_site;
end
$function$
