BEGIN; SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='30s';

DO $stop$ BEGIN RAISE EXCEPTION 'STOP: expected company source candidate, not production qualified';END $stop$;
DO $owner$ BEGIN IF current_user<>'postgres' THEN RAISE EXCEPTION 'installer role mismatch';END IF;END $owner$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.attach_approved_trade_link(uuid,uuid,text)') AND md5(prosrc)='d9be054adc99634402606404a60cd3e1' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.confirm_trade_company_link(uuid,uuid)') AND md5(prosrc)='5b74b0c8db0ef2a49ebedda5ee7ce050' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.request_trade_company_link(uuid,text,date)') AND md5(prosrc)='2e805be6aee6c2dc8915431a59b0ab83' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.respond_trade_company_link(uuid,text)') AND md5(prosrc)='1a4b7443180a7c4021f9b71c95aa0bcb' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.search_trade_company_links(text)') AND md5(prosrc)='80868e222df4a8ea115598655c5b2425' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.set_trade_company_link_enabled(boolean)') AND md5(prosrc)='1994d82c1e68211248c64d44eb511c16' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.trade_company_link_workspace()') AND md5(prosrc)='d9560adae54cbfe60d3d831fb126a2e3' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('private.trade_link_company_admin_id()') AND md5(prosrc)='18115ec89efafac4e81cf0e6fad1dc16' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres"]'::jsonb AND prosecdef=true AND provolatile='s' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('public.request_trade_company_link(uuid,text,date)') AND md5(prosrc)='55c4698e6834fb9e19603e5588e99565' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres", "service_role=X/postgres"]'::jsonb AND prosecdef=false AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('public.respond_trade_company_link(uuid,text)') AND md5(prosrc)='931dd8a02e6a2e2256e566080ce189f6' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres", "service_role=X/postgres"]'::jsonb AND prosecdef=false AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('public.search_trade_company_links(text)') AND md5(prosrc)='9e55fd84e69e81abdd5ead6848122acd' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres", "service_role=X/postgres"]'::jsonb AND prosecdef=false AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('public.set_trade_company_link_enabled(boolean)') AND md5(prosrc)='cfa6e4fe48967a2cdace71d9fd41f1d4' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres", "service_role=X/postgres"]'::jsonb AND prosecdef=false AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure('public.trade_company_link_workspace()') AND md5(prosrc)='13b2de37b3d78e9fed1e9e114fc2645c' AND pg_get_userbyid(proowner)='postgres' AND to_jsonb(proacl::text[])='["postgres=X/postgres", "authenticated=X/postgres", "service_role=X/postgres"]'::jsonb AND prosecdef=false AND provolatile='v' AND proconfig=ARRAY['search_path=""']::text[]) THEN RAISE EXCEPTION 'company link baseline changed';END IF;END $guard$;

CREATE OR REPLACE FUNCTION private.trade_link_company_admin_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select min(cm.company_id::text)::uuid from public.company_members cm
 where auth.uid() is not null and private.account_access_allowed()
 and cm.user_id=auth.uid() and cm.role::text in ('owner','admin')
 and (select count(distinct s.company_id) from public.company_members s where s.user_id=auth.uid())=1
 group by cm.user_id having count(distinct cm.company_id)=1
$function$
;

CREATE FUNCTION private.trade_link_company_admin_id(p_expected_company uuid) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $body$
BEGIN
 IF auth.uid() IS NULL OR p_expected_company IS NULL THEN RAISE EXCEPTION '会社とログイン状態を確認してください' USING ERRCODE='42501'; END IF;
 IF NOT pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(auth.uid())) THEN RAISE EXCEPTION 'アカウントを確認してください' USING ERRCODE='42501';END IF;
 PERFORM private.require_reauthentication_session();
 IF private.account_access_allowed() IS NOT TRUE THEN RAISE EXCEPTION 'アカウントを確認してください' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM public.company_members WHERE company_id=p_expected_company AND user_id=auth.uid() AND role::text IN ('owner','admin') FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION '会社への所属・管理権限が変更されています' USING ERRCODE='42501';END IF;
 RETURN p_expected_company;
END $body$;

CREATE FUNCTION private.request_trade_company_link(p_target_company_id uuid, p_local_role text, p_start_month date, p_expected_company uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.trade_link_company_admin_id(p_expected_company); rid uuid;
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
end $function$
;

CREATE FUNCTION private.respond_trade_company_link(p_request_id uuid, p_action text, p_expected_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.trade_link_company_admin_id(p_expected_company); r private.trade_company_link_requests%rowtype;
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
end $function$
;

CREATE FUNCTION private.search_trade_company_links(p_query text, p_expected_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.trade_link_company_admin_id(p_expected_company); q text:=trim(p_query);
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 if not coalesce((select enabled from private.trade_company_link_settings where company_id=cid),false) then raise exception '会社連携は停止中です'; end if;
 if char_length(q)<2 or char_length(q)>100 then raise exception '検索は2〜100文字で入力してください'; end if;
 return coalesce((select jsonb_agg(x) from (select c.id company_id,c.name company_name,c.address,c.corporate_number
 from public.companies c join private.trade_company_link_settings s on s.company_id=c.id and s.enabled
 where c.id<>cid and (strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.corporate_number,''),q)>0)
 order by c.name,c.id limit 30)x),'[]'::jsonb);
end $function$
;

CREATE FUNCTION private.set_trade_company_link_enabled(p_enabled boolean, p_expected_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.trade_link_company_admin_id(p_expected_company);
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 insert into private.trade_company_link_settings values(cid,p_enabled) on conflict(company_id) do update set enabled=excluded.enabled;
end $function$
;

CREATE FUNCTION private.trade_company_link_workspace(p_expected_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.trade_link_company_admin_id(p_expected_company);
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます'; end if;
 return jsonb_build_object('enabled',coalesce((select enabled from private.trade_company_link_settings where company_id=cid),false),
 'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'incoming',r.target_company_id=cid,
 'company_name',c.name,'start_month',r.start_month,'status',r.status,'created_at',r.created_at,
 'local_role',case when r.sender_company_id=cid then r.local_role when r.local_role='customer' then 'subcontractor' else 'customer' end) order by r.created_at desc)
 from private.trade_company_link_requests r join public.companies c on c.id=case when r.sender_company_id=cid then r.target_company_id else r.sender_company_id end
 where cid in(r.sender_company_id,r.target_company_id)),'[]'::jsonb));
end $function$
;

CREATE FUNCTION public.request_trade_company_link(p_target_company_id uuid, p_local_role text, p_start_month date, p_expected_company uuid)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.request_trade_company_link(p_target_company_id,p_local_role,p_start_month, p_expected_company)$function$
;

CREATE FUNCTION public.respond_trade_company_link(p_request_id uuid, p_action text, p_expected_company uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.respond_trade_company_link(p_request_id,p_action, p_expected_company)$function$
;

CREATE FUNCTION public.search_trade_company_links(p_query text, p_expected_company uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.search_trade_company_links(p_query, p_expected_company)$function$
;

CREATE FUNCTION public.set_trade_company_link_enabled(p_enabled boolean, p_expected_company uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.set_trade_company_link_enabled(p_enabled, p_expected_company)$function$
;

CREATE FUNCTION public.trade_company_link_workspace(p_expected_company uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.trade_company_link_workspace(p_expected_company)$function$
;

CREATE FUNCTION public.trade_company_link_contexts() RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $body$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(auth.uid())) THEN RAISE EXCEPTION 'ログイン状態を確認してください' USING ERRCODE='42501';END IF;
 PERFORM private.require_reauthentication_session();
 IF private.account_access_allowed() IS NOT TRUE THEN RAISE EXCEPTION 'アカウントを確認してください' USING ERRCODE='42501';END IF;
 IF (SELECT count(*) FROM public.company_members WHERE user_id=auth.uid() AND role::text IN('owner','admin'))>100 THEN RAISE EXCEPTION '会社一覧を確認してください' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('company_id',c.id,'company_name',c.name,'enabled',coalesce(s.enabled,false)) ORDER BY c.id),'[]'::jsonb) INTO result
 FROM public.company_members m JOIN public.companies c ON c.id=m.company_id LEFT JOIN private.trade_company_link_settings s ON s.company_id=c.id
 WHERE m.user_id=auth.uid() AND m.role::text IN('owner','admin');
 RETURN jsonb_build_object('contract_version',1,'actor_id',auth.uid(),'session_id',auth.jwt()->>'session_id','companies',result);
END $body$;

REVOKE ALL ON FUNCTION private.trade_link_company_admin_id(uuid) FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION private.request_trade_company_link(uuid,text,date,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private.request_trade_company_link(uuid,text,date,uuid) TO authenticated;

REVOKE ALL ON FUNCTION private.respond_trade_company_link(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private.respond_trade_company_link(uuid,text,uuid) TO authenticated;

REVOKE ALL ON FUNCTION private.search_trade_company_links(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private.search_trade_company_links(text,uuid) TO authenticated;

REVOKE ALL ON FUNCTION private.set_trade_company_link_enabled(boolean,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private.set_trade_company_link_enabled(boolean,uuid) TO authenticated;

REVOKE ALL ON FUNCTION private.trade_company_link_workspace(uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private.trade_company_link_workspace(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.request_trade_company_link(uuid,text,date,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.request_trade_company_link(uuid,text,date,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.respond_trade_company_link(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.respond_trade_company_link(uuid,text,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.search_trade_company_links(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.search_trade_company_links(text,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.set_trade_company_link_enabled(boolean,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.set_trade_company_link_enabled(boolean,uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.trade_company_link_workspace(uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.trade_company_link_workspace(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.trade_company_link_contexts() FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.trade_company_link_contexts() TO authenticated;

DO $acl$ BEGIN IF EXISTS(SELECT 1 FROM unnest(ARRAY['private.trade_link_company_admin_id(uuid)','private.request_trade_company_link(uuid,text,date,uuid)','private.respond_trade_company_link(uuid,text,uuid)','private.search_trade_company_links(text,uuid)','private.set_trade_company_link_enabled(boolean,uuid)','private.trade_company_link_workspace(uuid)','public.request_trade_company_link(uuid,text,date,uuid)','public.respond_trade_company_link(uuid,text,uuid)','public.search_trade_company_links(text,uuid)','public.set_trade_company_link_enabled(boolean,uuid)','public.trade_company_link_workspace(uuid)','public.trade_company_link_contexts()'])s(sig) JOIN pg_proc p ON p.oid=to_regprocedure(sig) CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.grantee<>p.proowner AND (a.grantee<>to_regrole('authenticated')::oid OR sig='private.trade_link_company_admin_id(uuid)' OR a.privilege_type<>'EXECUTE' OR a.is_grantable)) THEN RAISE EXCEPTION 'unexpected inherited function ACL';END IF;END $acl$;

COMMIT;
