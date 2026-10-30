-- Isolated fixture only. Auth JWT settings and policy configuration are synthetic.
-- Eight captured deployed function bodies/attributes are reproduced exactly.
create role anon;create role authenticated;create role service_role;
create schema auth;create schema private;create schema extensions;
grant usage on schema private,auth to authenticated;
create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$select hashtextextended('fixture-account:'||$1::text,0)$$;
create table private.account_deletion_access_restrictions(user_id uuid);
create table private.master_admins(user_id uuid,enabled boolean);
create function private.reauthentication_scope(text) returns text language sql immutable as $$select case when $1='master.feature.set' then 'master_feature' end$$;
create function private.reauthentication_required(text) returns boolean language sql stable as $$select $1='master_feature' and current_setting('fixture.reauth_required',true) is distinct from 'false'$$;
create function extensions.digest(text,text) returns bytea language sql immutable as $$select sha256(convert_to($1,'UTF8')) where $2='sha256'$$;
create table private.reauthentication_proofs(proof_hash text primary key,actor_id uuid,session_id uuid,operation text,target jsonb,secondary_credential_fingerprint text,consumed_at timestamptz,expires_at timestamptz);
create table public.user_secondary_credentials(user_id uuid,password_hash text);
create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid references auth.users(id),constraint master_feature_settings_feature_key_check check(feature_key in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')));
alter table private.master_feature_settings enable row level security;
revoke all on private.master_feature_settings from public,anon,authenticated;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.companies(id uuid primary key,name text,address text,corporate_number text,phone text,fax text,email text,company_seal_style text,company_seal_enabled boolean);
create table public.trade_companies(id uuid primary key,company_id uuid,name text,address text,corporate_number text,representative_name text,phone text,trade_role text,linked_company_id uuid,partner_company_id uuid);
create table private.partner_company_profile_extensions(company_id uuid,representative_name text);
create table private.company_seal_png_selection(company_id uuid,enabled boolean,version_id uuid);
create table private.company_seal_png_versions(id uuid,company_id uuid,png_bytes bytea,sha256 text);
create table private.trade_document_templates(company_id uuid,subject_kind text,payload jsonb);
CREATE OR REPLACE FUNCTION private.account_access_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$
;
revoke all on function private.account_access_allowed() from public,anon,authenticated,service_role;
grant execute on function private.account_access_allowed() to postgres;
grant execute on function private.account_access_allowed() to anon;
grant execute on function private.account_access_allowed() to authenticated;
grant execute on function private.account_access_allowed() to service_role;
CREATE OR REPLACE FUNCTION public.is_current_user_master_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
  select exists (
    select 1
    from private.master_admins ma
    where ma.user_id = auth.uid()
      and ma.enabled
  );
$function$
;
revoke all on function public.is_current_user_master_admin() from public,anon,authenticated,service_role;
grant execute on function public.is_current_user_master_admin() to postgres;
grant execute on function public.is_current_user_master_admin() to authenticated;
grant execute on function public.is_current_user_master_admin() to service_role;
CREATE OR REPLACE FUNCTION private.partner_company_profile_value(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('name',c.name,'address',c.address,'phone',c.phone,
 'email',c.email,'corporate_number',c.corporate_number,
 'representative_name',e.representative_name)
 from public.companies c left join private.partner_company_profile_extensions e on e.company_id=c.id
 where c.id=p_company_id
$function$
;
revoke all on function private.partner_company_profile_value(uuid) from public,anon,authenticated,service_role;
grant execute on function private.partner_company_profile_value(uuid) to postgres;
CREATE OR REPLACE FUNCTION private.require_reauthentication_session()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();sid uuid;
begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false)
  and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;
end $function$
;
revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role;
grant execute on function private.require_reauthentication_session() to postgres;
CREATE OR REPLACE FUNCTION private.consume_reauthentication_proof(p_operation text, p_target jsonb, p_proof text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); v_session uuid; consumed text;fingerprint text;
begin
 if actor is null or not private.account_access_allowed() or p_proof is null or p_proof !~ '^[0-9a-f]{64}$'
  or private.reauthentication_scope(p_operation) is null
  or not private.reauthentication_required(private.reauthentication_scope(p_operation)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 v_session:=private.require_reauthentication_session();
 begin v_session:=(auth.jwt()->>'session_id')::uuid;
 exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required'; end;
 if v_session is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
 if p_operation like 'master.%' and not public.is_current_user_master_admin() then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then
  raise sqlstate '42501' using message='reauthentication_required';
 end if;
 if not private.account_access_allowed() then raise sqlstate '42501' using message='reauthentication_required'; end if;
 perform 1 from auth.sessions s where s.id=v_session and s.user_id=actor
  and (s.not_after is null or s.not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required'; end if;
 -- Credential changes use one lock order, including primary recovery.
 if p_operation in('secondary_password.replace','secondary_password.change') then
  perform pg_advisory_xact_lock(hashtextextended('sko-secondary-password:'||actor::text,0));
  perform 1 from public.user_secondary_credentials where user_id=actor for update;
 end if;
 if p_operation in('secondary_password.change','attendance.manage') then
  select encode(extensions.digest(password_hash,'sha256'),'hex') into fingerprint
  from public.user_secondary_credentials where user_id=actor for share;
  if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 end if;
 update private.reauthentication_proofs p set consumed_at=clock_timestamp()
 where p.proof_hash=encode(extensions.digest(p_proof,'sha256'),'hex')
  and p.actor_id=actor and p.session_id=v_session and p.operation=p_operation
  and p.target=p_target and p.secondary_credential_fingerprint is not distinct from fingerprint
  and p.consumed_at is null and p.expires_at>clock_timestamp()
 returning proof_hash into consumed;
 if consumed is null then raise sqlstate '42501' using message='reauthentication_required'; end if;
end $function$
;
revoke all on function private.consume_reauthentication_proof(text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function private.consume_reauthentication_proof(text,jsonb,text) to postgres;
CREATE OR REPLACE FUNCTION public.current_master_feature_flags()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when auth.uid() is null then null
    else jsonb_build_object(
      'vehicle_management',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'vehicle_management'
        ), true),
      'route_assignment',
        coalesce((
          select mfs.enabled
          from private.master_feature_settings mfs
          where mfs.feature_key = 'route_assignment'
        ), true),
      'traffic_nearest_station', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_nearest_station'),false),
      'traffic_train_transfer', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_train_transfer'),false),
      'traffic_bus_stop', coalesce((select enabled from private.master_feature_settings where feature_key='traffic_bus_stop'),false)
    )
  end;
$function$
;
revoke all on function public.current_master_feature_flags() from public,anon,authenticated,service_role;
grant execute on function public.current_master_feature_flags() to postgres;
grant execute on function public.current_master_feature_flags() to authenticated;
grant execute on function public.current_master_feature_flags() to service_role;
CREATE OR REPLACE FUNCTION public.set_master_feature_enabled_with_proof(p_feature_key text, p_enabled boolean, p_proof text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.consume_reauthentication_proof('master.feature.set',jsonb_build_object('feature_key',p_feature_key,'enabled',p_enabled),p_proof);
 if p_feature_key not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop') or p_enabled is null then
  raise sqlstate '22023' using message='unsupported_master_feature';
 end if;
 insert into private.master_feature_settings(feature_key,enabled,updated_at,updated_by)
 values(p_feature_key,p_enabled,now(),auth.uid()) on conflict(feature_key) do update
 set enabled=excluded.enabled,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.current_master_feature_flags();
end $function$
;
revoke all on function public.set_master_feature_enabled_with_proof(text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.set_master_feature_enabled_with_proof(text,boolean,text) to postgres;
grant execute on function public.set_master_feature_enabled_with_proof(text,boolean,text) to authenticated;
grant execute on function public.set_master_feature_enabled_with_proof(text,boolean,text) to service_role;
CREATE OR REPLACE FUNCTION public.set_master_feature_enabled(p_feature_key text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or not public.is_current_user_master_admin() or not private.account_access_allowed() then
  raise sqlstate '42501' using message='master_administrator_access_required';
 end if;
 if private.reauthentication_required('master_feature') then raise sqlstate '42501' using message='reauthentication_required'; end if;
 if p_feature_key is null or p_feature_key not in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop') then
  raise exception 'unsupported master feature';
 end if;
 insert into private.master_feature_settings(feature_key,enabled,updated_at,updated_by)
 values(p_feature_key,p_enabled,now(),auth.uid()) on conflict(feature_key) do update
 set enabled=excluded.enabled,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.current_master_feature_flags();
end $function$
;
revoke all on function public.set_master_feature_enabled(text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.set_master_feature_enabled(text,boolean) to postgres,authenticated,service_role;
