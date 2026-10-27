-- Exact helper bodies read from production; Auth tables/JWT are synthetic only.
create table auth.users(id uuid primary key,is_anonymous boolean not null default false,banned_until timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
create function auth.jwt() returns jsonb language sql stable as $$
 select jsonb_build_object('role',coalesce(nullif(current_setting('test.jwt_role',true),''),'authenticated'),
 'is_anonymous',coalesce(nullif(current_setting('test.jwt_anon',true),''),'false'),
 'session_id',case when current_setting('test.live_sid',true)='false' then null
 else coalesce(nullif(current_setting('test.session_override',true),''),md5(nullif(current_setting('test.uid',true),'')||':session')::uuid::text) end);
$$;
CREATE OR REPLACE FUNCTION private.account_deletion_barrier_key(p_user uuid)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
 select pg_catalog.hashtextextended('sko:account-deletion:data-api:'||p_user::text,0)
$function$;
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
end $function$;
