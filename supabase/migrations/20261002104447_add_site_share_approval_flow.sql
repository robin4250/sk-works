create table if not exists private.site_share_inbox (
  data_item_id uuid primary key references private.company_data_delivery_items(id) on delete cascade,
  recipient_company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected')),
  responded_by uuid,
  responded_at timestamptz,
  accepted_site_id uuid references public.sites(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table private.site_share_inbox enable row level security;

create index if not exists site_share_inbox_recipient_status_idx
  on private.site_share_inbox(recipient_company_id,status,created_at desc);

create or replace function private.site_share_targets()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid()
    and m.role::text in ('owner','admin','manager')
  limit 1;
  if c is null then raise exception '管理者・サブ管理者だけが操作できます。'; end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'company_id',x.company_id,
        'company_name',x.company_name,
        'relation_label',x.relation_label
      )
      order by x.relation_label,x.company_name
    )
    from (
      select co.id company_id,co.name company_name,'下請け会社'::text relation_label
      from private.company_connections cc
      join public.companies co on co.id=cc.child_company_id
      where cc.parent_company_id=c and cc.status='accepted'
      union
      select co.id company_id,co.name company_name,'取引会社'::text relation_label
      from private.company_connections cc
      join public.companies co on co.id=cc.parent_company_id
      where cc.child_company_id=c and cc.status='accepted'
    ) x
  ),'[]'::jsonb);
end
$$;

create or replace function public.site_share_targets()
returns jsonb
language sql
set search_path=''
as $$ select private.site_share_targets() $$;

revoke all on function public.site_share_targets() from public,anon;
grant execute on function public.site_share_targets() to authenticated;

create or replace function private.send_site_share(
  p_site_id uuid,
  p_target_company_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  c uuid;
  cn text;
  s record;
  target uuid;
  target_name text;
  delivery_id uuid;
  data_id uuid;
  sent_count integer:=0;
begin
  select m.company_id,co.name into c,cn
  from public.company_members m
  join public.companies co on co.id=m.company_id
  where m.user_id=auth.uid()
    and m.role::text in ('owner','admin','manager')
  limit 1;
  if c is null then raise exception '管理者・サブ管理者だけが操作できます。'; end if;

  if p_target_company_ids is null
     or cardinality(p_target_company_ids) not between 1 and 100 then
    raise exception '送信先会社を選択してください。';
  end if;

  select st.*,cu.name as customer_name
  into s
  from public.sites st
  left join public.customers cu on cu.id=st.customer_id
  where st.id=p_site_id and st.company_id=c;
  if s.id is null then raise exception '現場が見つかりません。'; end if;

  foreach target in array p_target_company_ids loop
    if not exists(
      select 1 from private.company_connections cc
      where cc.status='accepted'
        and (
          (cc.parent_company_id=c and cc.child_company_id=target)
          or (cc.child_company_id=c and cc.parent_company_id=target)
        )
    ) then
      raise exception '接続済みの会社だけに送信できます。';
    end if;

    select co.name into target_name
    from public.companies co
    where co.id=target;
    if target_name is null then
      raise exception '送信先会社が見つかりません。';
    end if;

    delivery_id:=gen_random_uuid();
    insert into private.document_deliveries(
      id,sender_company_id,recipient_company_id,
      sender_name,recipient_name,sent_by,note
    )
    values(
      delivery_id,c,target,cn,target_name,auth.uid(),
      '現場データ共有'
    );

    insert into private.company_data_delivery_items(
      delivery_id,payload_kind,payload,company_path
    )
    values(
      delivery_id,
      'site_share',
      jsonb_build_object(
        'source_site_id',s.id,
        'name',coalesce(nullif(s.formal_name,''),s.name),
        'formal_name',coalesce(s.formal_name,''),
        'customer_name',coalesce(s.customer_name,''),
        'address',coalesce(s.address,''),
        'nearest_station',coalesce(s.nearest_station,''),
        'representative_name',coalesce(s.representative_name,''),
        'representative_phone',coalesce(s.representative_phone,''),
        'notes',coalesce(s.notes,''),
        'status',s.status,
        'latitude',s.latitude,
        'longitude',s.longitude
      ),
      jsonb_build_array(cn)
    )
    returning id into data_id;

    insert into private.site_share_inbox(
      data_item_id,recipient_company_id,status
    )
    values(data_id,target,'pending');

    insert into public.app_notifications(
      company_id,recipient_user_id,kind,title,body,action_key,action_id
    )
    select
      target,
      m.user_id,
      'approval',
      '現場データの承認が必要です',
      cn||'から現場「'||coalesce(nullif(s.formal_name,''),s.name)||
        '」が届いています。',
      'site_share_approval',
      data_id
    from public.company_members m
    where m.company_id=target
      and m.role::text in ('owner','admin','manager');

    sent_count:=sent_count+1;
  end loop;

  return sent_count;
end
$$;

create or replace function public.send_site_share(
  p_site_id uuid,
  p_target_company_ids uuid[]
)
returns integer
language sql
set search_path=''
as $$ select private.send_site_share(p_site_id,p_target_company_ids) $$;

revoke all on function public.send_site_share(uuid,uuid[]) from public,anon;
grant execute on function public.send_site_share(uuid,uuid[]) to authenticated;

create or replace function private.site_share_inbox()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid()
    and m.role::text in ('owner','admin','manager')
  limit 1;
  if c is null then raise exception '管理者・サブ管理者だけが確認できます。'; end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'data_item_id',i.id,
        'delivery_id',d.id,
        'sender_company_name',d.sender_name,
        'payload',i.payload,
        'status',s.status,
        'created_at',s.created_at
      )
      order by s.created_at desc
    )
    from private.site_share_inbox s
    join private.company_data_delivery_items i on i.id=s.data_item_id
    join private.document_deliveries d on d.id=i.delivery_id
    where s.recipient_company_id=c
      and s.status='pending'
      and i.payload_kind='site_share'
  ),'[]'::jsonb);
end
$$;

create or replace function public.site_share_inbox()
returns jsonb
language sql
set search_path=''
as $$ select private.site_share_inbox() $$;

revoke all on function public.site_share_inbox() from public,anon;
grant execute on function public.site_share_inbox() to authenticated;

create or replace function private.respond_site_share(
  p_data_item_id uuid,
  p_accept boolean
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
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

  if item.data_item_id is null then
    raise exception '受信した現場データが見つかりません。';
  end if;
  if item.status<>'pending' then
    raise exception 'この現場データは処理済みです。';
  end if;

  if not p_accept then
    update private.site_share_inbox
    set status='rejected',
        responded_by=auth.uid(),
        responded_at=now()
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
$$;

create or replace function public.respond_site_share(
  p_data_item_id uuid,
  p_accept boolean
)
returns uuid
language sql
set search_path=''
as $$ select private.respond_site_share(p_data_item_id,p_accept) $$;

revoke all on function public.respond_site_share(uuid,boolean) from public,anon;
grant execute on function public.respond_site_share(uuid,boolean) to authenticated;
