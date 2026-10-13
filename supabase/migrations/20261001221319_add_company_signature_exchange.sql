create or replace function private.company_signature_sources()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',d.id,
      'kind','daily_report_signature',
      'name',d.report_date::text||' / '||coalesce(s.name,'現場')||' / '||
        coalesce(nullif(d.signer_name,''),nullif(d.representative_signer_name,''),nullif(d.supervisor_signer_name,''),'サイン'),
      'group',coalesce(s.name,'現場')
    ) order by d.report_date desc,d.id)
    from public.daily_reports d
    left join public.sites s on s.id=d.site_id
    where d.company_id=c
      and (
        d.signature_json is not null
        or d.representative_signature_json is not null
        or d.supervisor_signature_json is not null
      )
  ),'[]'::jsonb);
end
$$;

create or replace function private.send_connected_signature_data(
  p_request_id uuid,
  p_target_company_id uuid,
  p_report_ids uuid[],
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare c uuid; cn text; tn text; r record;
begin
  select m.company_id,co.name into c,cn
  from public.company_members m
  join public.companies co on co.id=m.company_id
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;

  if p_request_id is null
     or p_target_company_id is null
     or p_report_ids is null
     or cardinality(p_report_ids) not between 1 and 100
     or length(coalesce(p_note,''))>2000 then
    raise exception '送信内容を確認してください。';
  end if;

  if not exists(
    select 1 from private.company_connections cc
    where cc.child_company_id=c
      and cc.parent_company_id=p_target_company_id
      and cc.status='accepted'
  ) then
    raise exception '接続済みの親会社を選択してください。';
  end if;

  select name into tn from public.companies where id=p_target_company_id;
  if tn is null then raise exception '送信先会社を確認してください。'; end if;

  if exists(
    select 1 from private.document_deliveries d
    where d.id=p_request_id and d.sender_company_id=c and d.sent_by=auth.uid()
  ) then return p_request_id; end if;

  insert into private.document_deliveries(
    id,sender_company_id,recipient_company_id,sender_name,recipient_name,sent_by,note
  ) values(
    p_request_id,c,p_target_company_id,cn,tn,auth.uid(),coalesce(p_note,'')
  );

  for r in
    select d.*,s.name site_name
    from public.daily_reports d
    left join public.sites s on s.id=d.site_id
    where d.company_id=c and d.id=any(p_report_ids)
  loop
    insert into private.company_data_delivery_items(
      delivery_id,payload_kind,payload,company_path
    ) values(
      p_request_id,
      'signature',
      jsonb_build_object(
        'source_daily_report_id',r.id,
        'report_date',r.report_date,
        'site_name',coalesce(r.site_name,''),
        'signer_name',coalesce(r.signer_name,''),
        'signature_json',r.signature_json,
        'representative_signer_name',coalesce(r.representative_signer_name,''),
        'representative_signature_json',r.representative_signature_json,
        'supervisor_signer_name',coalesce(r.supervisor_signer_name,''),
        'supervisor_signature_json',r.supervisor_signature_json,
        'signed_at',r.signed_at
      ),
      jsonb_build_array(cn)
    );
  end loop;

  if not exists(
    select 1 from private.company_data_delivery_items i
    where i.delivery_id=p_request_id and i.payload_kind='signature'
  ) then
    delete from private.document_deliveries where id=p_request_id;
    raise exception '送信できるサインがありません。';
  end if;

  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select p_target_company_id,m.user_id,'info',
    '協力会社からサイン一覧が届きました',
    cn||'からのサイン一覧を確認してください。',
    'company_document_delivery',p_request_id
  from public.company_members m
  where m.company_id=p_target_company_id and m.role::text in ('owner','admin');

  return p_request_id;
end
$$;

create or replace function public.company_signature_sources()
returns jsonb language sql set search_path=''
as $$ select private.company_signature_sources() $$;

create or replace function public.send_connected_signature_data(
  p_request_id uuid,
  p_target_company_id uuid,
  p_report_ids uuid[],
  p_note text default ''
)
returns uuid language sql set search_path=''
as $$ select private.send_connected_signature_data(
  p_request_id,p_target_company_id,p_report_ids,p_note
) $$;

revoke all on function public.company_signature_sources() from public,anon;
revoke all on function public.send_connected_signature_data(uuid,uuid,uuid[],text)
from public,anon;
grant execute on function public.company_signature_sources() to authenticated;
grant execute on function public.send_connected_signature_data(uuid,uuid,uuid[],text)
to authenticated;
