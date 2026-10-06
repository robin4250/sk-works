-- Unify registered site fields across detail/edit and make trade-company deletion reference-safe.

create or replace function private.site_directory_rows_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  cid uuid;
  result jsonb;
begin
  if auth.uid() is null then raise exception 'ログインが必要です'; end if;
  select company_id into cid
  from public.company_members
  where user_id=auth.uid()
  limit 1;
  if cid is null then raise exception '会社への所属が必要です'; end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(r) ||
      jsonb_build_object(
        'customer_id', coalesce(s.customer_id::text,''),
        'manager_worker_id', coalesce(s.manager_worker_id::text,''),
        'formal_name',coalesce(s.formal_name,''),
        'nearest_station',coalesce(s.nearest_station,''),
        'representative_name',coalesce(s.representative_name,''),
        'representative_phone',coalesce(s.representative_phone,'')
      )
      order by s.created_at desc
    ),
    '[]'::jsonb
  )
  into result
  from public.site_directory_rows() r
  join public.sites s on s.id=r.id and s.company_id=cid;

  return result;
end
$$;

create or replace function private.site_information_request(
  p_action text,
  p_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid:=auth.uid();
  cid uuid;
  can_review boolean;
  sid uuid;
  current_values jsonb;
  values_to_set jsonb:='{}';
  before_values jsonb:='{}';
  proposed jsonb:='{}';
  entry record;
  req private.site_information_requests%rowtype;
  normalized_value text;
  parsed_uuid uuid;
begin
  if uid is null then raise exception 'ログインが必要です'; end if;

  select company_id into cid
  from public.company_members
  where user_id=uid
  limit 1;
  if cid is null then raise exception '会社への所属が必要です'; end if;

  select exists(
    select 1
    from public.company_members
    where company_id=cid
      and user_id=uid
      and role::text in ('owner','admin','manager')
  ) or exists(
    select 1
    from public.company_approval_assignees
    where company_id=cid and user_id=uid
  )
  into can_review;

  if p_action='list' then
    return coalesce((
      select jsonb_agg(
        to_jsonb(r)||
        jsonb_build_object(
          'site_name',s.name,
          'can_review',can_review
        )
        order by r.created_at desc
      )
      from private.site_information_requests r
      join public.sites s on s.id=r.site_id
      where r.company_id=cid
        and (can_review or r.requested_by=uid)
        and (r.status='pending' or r.requested_by=uid)
    ),'[]'::jsonb);
  end if;

  if p_action in ('approve','reject') then
    if not can_review then raise exception '承認権限がありません'; end if;

    select *
    into req
    from private.site_information_requests
    where id=(p_data->>'id')::uuid
      and company_id=cid
    for update;

    if not found or req.status<>'pending' then
      raise exception 'この申請は処理済みです';
    end if;

    if p_action='reject' then
      if nullif(trim(p_data->>'reason'),'') is null then
        raise exception '差し戻す理由を入力してください';
      end if;

      update private.site_information_requests
      set status='rejected',
          reason=p_data->>'reason',
          reviewed_by=uid,
          reviewed_at=now()
      where id=req.id;
      return '{}'::jsonb;
    end if;

    sid:=req.site_id;
  else
    if p_action<>'submit' then raise exception '操作を確認してください'; end if;
    sid:=(p_data->>'site_id')::uuid;
  end if;

  select to_jsonb(s)
  into current_values
  from public.sites s
  where id=sid and company_id=cid
  for update;

  if not found then raise exception '現場が見つかりません'; end if;

  if p_action='approve' then
    for entry in select * from jsonb_each(req.before_values)
    loop
      if coalesce(current_values->>entry.key,'') <>
         coalesce(entry.value#>>'{}','') then
        raise exception '申請後に情報が更新されました。再申請してください';
      end if;
    end loop;
    values_to_set:=req.proposed_values;
  else
    if jsonb_typeof(p_data->'values') is distinct from 'object' then
      raise exception '入力内容を確認してください';
    end if;

    for entry in select * from jsonb_each_text(p_data->'values')
    loop
      if entry.key not in (
        'name',
        'customer_id',
        'status',
        'formal_name',
        'manager_worker_id',
        'representative_name',
        'representative_phone',
        'address',
        'nearest_station',
        'starts_at',
        'ends_at',
        'notes'
      ) then
        raise exception '変更できない項目です';
      end if;

      normalized_value:=trim(entry.value);

      if entry.key in ('starts_at','ends_at') then
        normalized_value:=replace(normalized_value,'/','-');
        if normalized_value<>'' then
          perform normalized_value::date;
        end if;
      end if;

      if entry.key='name' and normalized_value='' then
        raise exception '現場名を入力してください';
      end if;

      if entry.key='customer_id' then
        if normalized_value='' then
          raise exception '登録済みの取引会社から取引先を選択してください';
        end if;
        parsed_uuid:=normalized_value::uuid;
        if not exists(
          select 1
          from public.trade_companies tc
          where tc.company_id=cid
            and tc.customer_id=parsed_uuid
            and tc.trade_role in ('customer','both')
        ) then
          raise exception '登録済みの取引会社から取引先を選択してください';
        end if;
      end if;

      if entry.key='manager_worker_id' and normalized_value<>'' then
        parsed_uuid:=normalized_value::uuid;
        if not exists(
          select 1
          from public.workers w
          where w.id=parsed_uuid
            and w.company_id=cid
            and w.affiliation='employee'
        ) then
          raise exception '担当者を確認してください';
        end if;
      end if;

      if entry.key='status' and normalized_value not in (
        'preparation','active','paused','completed'
      ) then
        raise exception '状態を確認してください';
      end if;

      if length(normalized_value)>2000 then
        raise exception '入力は2000文字以内にしてください';
      end if;

      if coalesce(current_values->>entry.key,'')=normalized_value then
        continue;
      end if;

      if nullif(trim(current_values->>entry.key),'') is null
         and entry.key not in ('customer_id','status') then
        values_to_set:=values_to_set||
          jsonb_build_object(entry.key,normalized_value);
      else
        before_values:=before_values||
          jsonb_build_object(entry.key,current_values->entry.key);
        proposed:=proposed||
          jsonb_build_object(entry.key,normalized_value);
      end if;
    end loop;

    if proposed<>'{}'::jsonb then
      insert into private.site_information_requests(
        company_id,
        site_id,
        requested_by,
        before_values,
        proposed_values
      )
      values(
        cid,
        sid,
        uid,
        before_values,
        proposed
      )
      returning * into req;
    end if;
  end if;

  update public.sites
  set
    name=case when values_to_set?'name'
      then values_to_set->>'name' else name end,
    customer_id=case when values_to_set?'customer_id'
      then nullif(values_to_set->>'customer_id','')::uuid else customer_id end,
    status=case when values_to_set?'status'
      then values_to_set->>'status' else status end,
    formal_name=case when values_to_set?'formal_name'
      then nullif(values_to_set->>'formal_name','') else formal_name end,
    manager_worker_id=case when values_to_set?'manager_worker_id'
      then nullif(values_to_set->>'manager_worker_id','')::uuid else manager_worker_id end,
    representative_name=case when values_to_set?'representative_name'
      then nullif(values_to_set->>'representative_name','') else representative_name end,
    representative_phone=case when values_to_set?'representative_phone'
      then nullif(values_to_set->>'representative_phone','') else representative_phone end,
    address=case when values_to_set?'address'
      then nullif(values_to_set->>'address','') else address end,
    nearest_station=case when values_to_set?'nearest_station'
      then nullif(values_to_set->>'nearest_station','') else nearest_station end,
    starts_at=case when values_to_set?'starts_at'
      then nullif(values_to_set->>'starts_at','')::date else starts_at end,
    ends_at=case when values_to_set?'ends_at'
      then nullif(values_to_set->>'ends_at','')::date else ends_at end,
    notes=case when values_to_set?'notes'
      then nullif(values_to_set->>'notes','') else notes end,
    updated_at=case when values_to_set<>'{}'::jsonb then now() else updated_at end
  where id=sid and company_id=cid;

  if p_action='approve' then
    update private.site_information_requests
    set status='approved',
        reviewed_by=uid,
        reviewed_at=now()
    where id=req.id;
  end if;

  return jsonb_build_object(
    'pending',proposed<>'{}'::jsonb,
    'request_id',req.id
  );
end
$$;

create or replace function private.delete_trade_company_checked(
  p_trade_company_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cid uuid;
  tc public.trade_companies%rowtype;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  select *
  into tc
  from public.trade_companies
  where id=p_trade_company_id and company_id=cid
  for update;

  if not found then
    raise exception '取引会社が見つかりません。';
  end if;

  if tc.linked_company_id is not null then
    raise exception 'この取引会社はSKO連携中のため削除できません。先に会社連携を解除してください';
  end if;

  if tc.customer_id is not null then
    if exists(
      select 1 from public.sites
      where company_id=cid and customer_id=tc.customer_id
    ) then
      raise exception 'この取引会社は現場で使用されているため削除できません';
    end if;

    if exists(
      select 1 from public.invoices
      where company_id=cid and customer_id=tc.customer_id
    ) then
      raise exception 'この取引会社は請求書で使用されているため削除できません';
    end if;
  end if;

  if tc.partner_company_id is not null then
    if exists(
      select 1 from public.payment_certificates
      where company_id=cid and partner_company_id=tc.partner_company_id
    ) then
      raise exception 'この協力会社は支払証明書で使用されているため削除できません';
    end if;

    if exists(
      select 1 from public.workers
      where company_id=cid and partner_company_id=tc.partner_company_id
    ) then
      raise exception 'この協力会社は従業員情報で使用されているため削除できません';
    end if;
  end if;

  delete from public.trade_companies
  where id=tc.id and company_id=cid;

  if tc.customer_id is not null
     and not exists(
       select 1 from public.trade_companies
       where company_id=cid and customer_id=tc.customer_id
     ) then
    delete from public.customers
    where id=tc.customer_id and company_id=cid;
  end if;

  if tc.partner_company_id is not null
     and not exists(
       select 1 from public.trade_companies
       where company_id=cid and partner_company_id=tc.partner_company_id
     ) then
    delete from public.partner_companies
    where id=tc.partner_company_id and company_id=cid;
  end if;

  if exists(
    select 1 from public.trade_companies
    where id=p_trade_company_id and company_id=cid
  ) then
    raise exception '取引会社を削除できませんでした';
  end if;

  return jsonb_build_object('deleted',true,'id',p_trade_company_id);
end
$$;

create or replace function private.delete_trade_company(
  p_trade_company_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.delete_trade_company_checked(p_trade_company_id);
end
$$;

create or replace function public.delete_trade_company_checked(
  p_trade_company_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.delete_trade_company_checked(p_trade_company_id)
$$;

revoke all on function private.delete_trade_company_checked(uuid)
from public, anon, authenticated;

revoke all on function public.delete_trade_company_checked(uuid)
from public, anon;

grant execute on function public.delete_trade_company_checked(uuid)
to authenticated;
