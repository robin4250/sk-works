create or replace function private.site_information_request(
  p_action text,
  p_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
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
    for entry in
      select * from jsonb_each(req.before_values)
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

    for entry in
      select * from jsonb_each_text(p_data->'values')
    loop
      if entry.key not in (
        'name',
        'formal_name',
        'address',
        'nearest_station',
        'representative_name',
        'representative_phone',
        'notes',
        'status'
      ) then
        raise exception '変更できない項目です';
      end if;

      if length(entry.value)>2000 then
        raise exception '入力は2000文字以内にしてください';
      end if;

      if entry.key='name' and nullif(trim(entry.value),'') is null then
        raise exception '現場名を入力してください';
      end if;

      if entry.key='status' and trim(entry.value) <> 'completed' then
        raise exception '終了申請の内容を確認してください';
      end if;

      if coalesce(current_values->>entry.key,'')=
         coalesce(trim(entry.value),'') then
        continue;
      end if;

      if entry.key='status' then
        before_values:=before_values||
          jsonb_build_object(entry.key,current_values->entry.key);
        proposed:=proposed||
          jsonb_build_object(entry.key,trim(entry.value));
      elsif nullif(trim(current_values->>entry.key),'') is null then
        values_to_set:=values_to_set||
          jsonb_build_object(entry.key,trim(entry.value));
      else
        before_values:=before_values||
          jsonb_build_object(entry.key,current_values->entry.key);
        proposed:=proposed||
          jsonb_build_object(entry.key,trim(entry.value));
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
    formal_name=case when values_to_set?'formal_name'
      then values_to_set->>'formal_name' else formal_name end,
    address=case when values_to_set?'address'
      then values_to_set->>'address' else address end,
    nearest_station=case when values_to_set?'nearest_station'
      then values_to_set->>'nearest_station' else nearest_station end,
    representative_name=case when values_to_set?'representative_name'
      then values_to_set->>'representative_name' else representative_name end,
    representative_phone=case when values_to_set?'representative_phone'
      then values_to_set->>'representative_phone' else representative_phone end,
    notes=case when values_to_set?'notes'
      then values_to_set->>'notes' else notes end,
    status=case when values_to_set?'status'
      then values_to_set->>'status' else status end,
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