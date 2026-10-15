-- Approval-first company relationships. No payroll or contract prices are copied.
-- Verified production definitions: refuse to replace an unexpected endpoint.
do $guard$
begin
 if to_regprocedure('private.confirm_trade_company_link(uuid,uuid)') is null
 or md5(pg_get_functiondef('private.confirm_trade_company_link(uuid,uuid)'::regprocedure)) <> '46272a03a2af799f623f400df8149bc5'
 or to_regprocedure('public.confirm_trade_company_link(uuid,uuid)') is null
 or md5(pg_get_functiondef('public.confirm_trade_company_link(uuid,uuid)'::regprocedure)) <> 'e8edc3fae4174fbeeecca0b81a798760' then
  raise exception '会社連携の既存定義が変更されています。バックアップと差分を確認してください';
 end if;
end $guard$;

-- Dedicated boundary: the shared legacy helper also permits manager accounts.
create function private.trade_link_company_admin_id() returns uuid
language sql stable security definer set search_path='' as $function$
 select cm.company_id from public.company_members cm
 where auth.uid() is not null and private.account_access_allowed()
 and cm.user_id=auth.uid() and cm.role::text in ('owner','admin')
 order by cm.company_id limit 1
$function$;
revoke all on function private.trade_link_company_admin_id() from public,anon,authenticated;
alter table private.company_connections add column if not exists link_start_month date;
create table private.trade_company_link_settings (
 company_id uuid primary key references public.companies(id), enabled boolean not null default false
);
create table private.trade_company_link_requests (
 id uuid primary key default gen_random_uuid(), sender_company_id uuid not null references public.companies(id),
 target_company_id uuid not null references public.companies(id), local_role text not null check(local_role in ('customer','subcontractor')),
 start_month date not null check(extract(day from start_month)=1),
 status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled')),
 created_by uuid not null, created_at timestamptz not null default now(), responded_by uuid, responded_at timestamptz,
 check(sender_company_id<>target_company_id)
);
create unique index trade_link_one_pending_pair on private.trade_company_link_requests
 (least(sender_company_id,target_company_id), greatest(sender_company_id,target_company_id)) where status='pending';
alter table private.trade_company_link_settings enable row level security;
alter table private.trade_company_link_requests enable row level security;
revoke all on private.trade_company_link_settings, private.trade_company_link_requests from public,anon,authenticated;

create function private.trade_company_link_workspace() returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.trade_link_company_admin_id();
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 return jsonb_build_object('enabled',coalesce((select enabled from private.trade_company_link_settings where company_id=cid),false),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'incoming',r.target_company_id=cid,
 'company_name',c.name,'start_month',r.start_month,'status',r.status,'created_at',r.created_at,
 'local_role',case when r.sender_company_id=cid then r.local_role when r.local_role='customer' then 'subcontractor' else 'customer' end) order by r.created_at desc)
 from private.trade_company_link_requests r join public.companies c on c.id=case when r.sender_company_id=cid then r.target_company_id else r.sender_company_id end
 where cid in(r.sender_company_id,r.target_company_id)),'[]'::jsonb));
end $$;
create function private.set_trade_company_link_enabled(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.trade_link_company_admin_id();
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 insert into private.trade_company_link_settings values(cid,p_enabled) on conflict(company_id) do update set enabled=excluded.enabled;
end $$;
create function private.search_trade_company_links(p_query text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.trade_link_company_admin_id(); q text:=trim(p_query);
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 if not coalesce((select enabled from private.trade_company_link_settings where company_id=cid),false) then raise exception '会社連携は停止中です'; end if;
 if char_length(q)<2 or char_length(q)>100 then raise exception '検索は2〜100文字で入力してください'; end if;
 return coalesce((select jsonb_agg(x) from (select c.id company_id,c.name company_name,c.address,c.corporate_number
 from public.companies c join private.trade_company_link_settings s on s.company_id=c.id and s.enabled
 where c.id<>cid and (strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.corporate_number,''),q)>0)
 order by c.name,c.id limit 30)x),'[]'::jsonb);
end $$;
create function private.request_trade_company_link(p_target_company_id uuid,p_local_role text,p_start_month date) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.trade_link_company_admin_id(); rid uuid;
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 if cid=p_target_company_id or p_local_role not in('customer','subcontractor') or p_start_month is null or extract(day from p_start_month)<>1 then raise exception '申請内容が不正です'; end if;
 if (select count(*) from private.trade_company_link_settings where company_id in(cid,p_target_company_id) and enabled)<>2 then raise exception '会社連携は停止中です'; end if;
 insert into private.trade_company_link_requests(sender_company_id,target_company_id,local_role,start_month,created_by)
 values(cid,p_target_company_id,p_local_role,p_start_month,auth.uid()) returning id into rid;
 insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)
 select p_target_company_id,m.user_id,'company_link_request','会社連携の申請があります',
  '連携開始月と会社情報を確認し、承認または却下してください。','company_link_request',rid
 from public.company_members m where m.company_id=p_target_company_id and m.role::text in('owner','admin');
 return rid;
end $$;

-- Preserve local contact data; only identity and reciprocal directory roles change.
create function private.attach_approved_trade_link(p_owner uuid,p_other uuid,p_role text) returns void language plpgsql security definer set search_path='' as $$
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
  select count(*),min(id::text)::uuid into n,legacy_id from public.customers where company_id=p_owner and lower(trim(name))=lower(trim(tc.name));
  if n>1 then raise exception '同名の取引先が複数あります。請求先を確認・整理してから再承認してください'; end if;
  if legacy_id is null then
   insert into public.customers(company_id,name,billing_name,billing_address) values(p_owner,tc.name,tc.name,tc.address) returning id into legacy_id;
  end if;
  update public.trade_companies set customer_id=legacy_id where id=tid and company_id=p_owner;
 elsif p_role='subcontractor' and tc.partner_company_id is null then
  select count(*),min(id::text)::uuid into n,legacy_id from public.partner_companies where company_id=p_owner and lower(trim(name))=lower(trim(tc.name));
  if n>1 then raise exception '同名の協力会社が複数あります。契約先を確認・整理してから再承認してください'; end if;
  if legacy_id is null then
   insert into public.partner_companies(company_id,name,phone,email,address,postal_code,trade_role,status)
   values(p_owner,tc.name,tc.phone,tc.email,tc.address,tc.postal_code,'subcontractor','active') returning id into legacy_id;
  end if;
  update public.trade_companies set partner_company_id=legacy_id where id=tid and company_id=p_owner;
 end if;
end $$;
create function private.respond_trade_company_link(p_request_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.trade_link_company_admin_id(); r private.trade_company_link_requests%rowtype;
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 select * into r from private.trade_company_link_requests where id=p_request_id for update;
 if r.id is null or r.status<>'pending' then raise exception '申請は処理済み、または見つかりません'; end if;
 if p_action='cancel' then
  if cid<>r.sender_company_id then raise exception '送信者のみ取消できます'; end if;
 elsif p_action in('accept','reject') then
  if cid<>r.target_company_id then raise exception '受信側のみ承認できます'; end if;
 else raise exception '操作が不正です'; end if;
 if p_action='accept' then
  if (select count(*) from private.trade_company_link_settings where company_id in(r.sender_company_id,r.target_company_id) and enabled)<>2 then raise exception '会社連携は停止中です'; end if;
  -- Stable lock order prevents opposing approvals deadlocking.
  perform pg_advisory_xact_lock(hashtextextended(least(r.sender_company_id,r.target_company_id)::text,0));
  perform pg_advisory_xact_lock(hashtextextended(greatest(r.sender_company_id,r.target_company_id)::text,0));
  perform private.attach_approved_trade_link(r.sender_company_id,r.target_company_id,r.local_role);
  perform private.attach_approved_trade_link(r.target_company_id,r.sender_company_id,case when r.local_role='customer' then 'subcontractor' else 'customer' end);
  insert into private.company_connections(parent_company_id,child_company_id,status,requested_by,responded_by,updated_at,link_start_month)
  values(case when r.local_role='customer' then r.target_company_id else r.sender_company_id end,
    case when r.local_role='customer' then r.sender_company_id else r.target_company_id end,
    'accepted',r.created_by,auth.uid(),now(),r.start_month)
  on conflict(parent_company_id,child_company_id) do update set status='accepted',requested_by=excluded.requested_by,
    responded_by=excluded.responded_by,updated_at=excluded.updated_at,link_start_month=excluded.link_start_month;
 end if;
 update private.trade_company_link_requests set status=case p_action when 'accept' then 'accepted' when 'reject' then 'rejected' else 'cancelled' end,
 responded_by=auth.uid(),responded_at=now() where id=r.id;
 insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)
 select m.company_id,m.user_id,'company_link_request','会社連携申請の状況が更新されました',
  case p_action when 'accept' then '承認され、双方の会社一覧へ反映されました。' when 'reject' then '申請は却下されました。' else '申請は取り消されました。' end,
  'company_link_request',r.id
 from public.company_members m where m.company_id in(r.sender_company_id,r.target_company_id) and m.role::text in('owner','admin');
end $$;

-- Old merge endpoint cannot bypass reciprocal approval.
create or replace function private.confirm_trade_company_link(p_trade_company_id uuid,p_linked_company_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin raise exception '会社検索から連携申請し、相手の承認を受けてください'; end $$;

revoke all on function private.trade_company_link_workspace(),private.set_trade_company_link_enabled(boolean),private.search_trade_company_links(text),private.request_trade_company_link(uuid,text,date),private.respond_trade_company_link(uuid,text),private.attach_approved_trade_link(uuid,uuid,text) from public,anon,authenticated;
create function public.trade_company_link_workspace() returns jsonb language sql security invoker set search_path='' as $$select private.trade_company_link_workspace()$$;
create function public.set_trade_company_link_enabled(p_enabled boolean) returns void language sql security invoker set search_path='' as $$select private.set_trade_company_link_enabled(p_enabled)$$;
create function public.search_trade_company_links(p_query text) returns jsonb language sql security invoker set search_path='' as $$select private.search_trade_company_links(p_query)$$;
create function public.request_trade_company_link(p_target_company_id uuid,p_local_role text,p_start_month date) returns uuid language sql security invoker set search_path='' as $$select private.request_trade_company_link(p_target_company_id,p_local_role,p_start_month)$$;
create function public.respond_trade_company_link(p_request_id uuid,p_action text) returns void language sql security invoker set search_path='' as $$select private.respond_trade_company_link(p_request_id,p_action)$$;
revoke all on function public.trade_company_link_workspace(),public.set_trade_company_link_enabled(boolean),public.search_trade_company_links(text),public.request_trade_company_link(uuid,text,date),public.respond_trade_company_link(uuid,text) from public,anon;
grant execute on function public.trade_company_link_workspace(),public.set_trade_company_link_enabled(boolean),public.search_trade_company_links(text),public.request_trade_company_link(uuid,text,date),public.respond_trade_company_link(uuid,text) to authenticated;
grant execute on function private.trade_company_link_workspace(),private.set_trade_company_link_enabled(boolean),private.search_trade_company_links(text),private.request_trade_company_link(uuid,text,date),private.respond_trade_company_link(uuid,text) to authenticated;
