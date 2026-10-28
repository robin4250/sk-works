\set ON_ERROR_STOP on
-- Synthetic auth/proof boundary. Does not prove GoTrue/JWT or key ownership.
create schema private;
create schema auth;
do $$ begin
 if not exists(select from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create function auth.uid() returns uuid language sql as $$
 select nullif(current_setting('fixture.actor',true),'')::uuid
$$;
create function private.require_reauthentication_session() returns uuid
language plpgsql as $$ begin
 if current_setting('fixture.session',true) is distinct from 'live' or auth.uid() is null then
   raise sqlstate '42501' using message='invalid session';
 end if;
 return auth.uid();
end $$;
create function public.is_current_user_master_admin() returns boolean
language sql as $$ select current_setting('fixture.master',true)='yes' $$;
create table private.proof_fixture(used boolean not null default false);
insert into private.proof_fixture default values;
create function private.consume_reauthentication_proof(operation text,target jsonb,proof text)
returns void language plpgsql as $$ begin
 if operation is distinct from 'master.feature.set' or target is distinct from
   jsonb_build_object('feature_key','qr_attendance','enabled',proof='fixture-bound-proof')
   or proof not in ('fixture-bound-proof','fixture-off-proof') or (select used from private.proof_fixture) then
   raise sqlstate '42501' using message='invalid proof';
 end if;
 update private.proof_fixture set used=true;
end $$;
create table private.master_feature_settings(feature_key text primary key,
 enabled boolean not null,updated_at timestamptz,updated_by uuid);
insert into private.master_feature_settings values('vehicle_management',true,null,null);
\ir qr-master-gate.sql.review-only
\ir qr-master-contract.sql.review-only
select set_config('fixture.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('fixture.session','live',false);
select set_config('fixture.master','no',false);
do $$ declare result jsonb; begin
 result:=qr_attendance_private.master_feature_fragment();
 if result is distinct from '{"qr_attendance_contract_version":1,"qr_attendance":false}'::jsonb then
   raise exception 'missing QR flag not OFF';
 end if;
 begin
   perform qr_attendance_private.set_master_feature_with_proof(true,'fixture-bound-proof');
   raise exception 'non-master accepted';
 exception when insufficient_privilege then null; end;
 if (select used from private.proof_fixture) then raise exception 'non-master consumed proof'; end if;
end $$;
select set_config('fixture.master','yes',false);
do $$ begin
 begin
   perform qr_attendance_private.set_master_feature_with_proof(null,'fixture-bound-proof');
   raise exception 'null accepted';
 exception when invalid_parameter_value then null; end;
 begin
   perform qr_attendance_private.set_master_feature_with_proof(true,'wrong');
   raise exception 'wrong proof accepted';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from private.master_feature_settings where feature_key='qr_attendance') then
   raise exception 'rejected request changed flag';
 end if;
 if qr_attendance_private.set_master_feature_with_proof(true,'fixture-bound-proof') is distinct from
   '{"qr_attendance_contract_version":1,"qr_attendance":true}'::jsonb then raise exception 'enable failed'; end if;
 perform qr_attendance_private.require_enabled();
 begin
   perform qr_attendance_private.set_master_feature_with_proof(true,'fixture-bound-proof');
   raise exception 'replayed proof accepted';
 exception when insufficient_privilege then null; end;
 if not exists(select 1 from private.master_feature_settings where feature_key='qr_attendance'
   and enabled and updated_by=auth.uid() and updated_at is not null) then raise exception 'attribution missing'; end if;
 if not (select enabled from private.master_feature_settings where feature_key='vehicle_management') then
   raise exception 'unrelated flag changed'; end if;
 update private.proof_fixture set used=false; -- synthetic issuance of a new OFF proof
 if qr_attendance_private.set_master_feature_with_proof(false,'fixture-off-proof') is distinct from
   '{"qr_attendance_contract_version":1,"qr_attendance":false}'::jsonb then raise exception 'disable failed'; end if;
 begin perform qr_attendance_private.require_enabled(); raise exception 'OFF gate accepted';
 exception when insufficient_privilege then null; end;
 if (select count(*) from private.master_feature_settings) <> 2 then raise exception 'OFF deleted settings'; end if;
 if has_function_privilege('authenticated','qr_attendance_private.set_master_feature_with_proof(boolean,text)','EXECUTE')
 or has_function_privilege('anon','qr_attendance_private.master_feature_fragment()','EXECUTE') then
   raise exception 'internal contract exposed'; end if;
end $$;
select set_config('fixture.session','expired',false);
do $$ begin
 begin perform qr_attendance_private.master_feature_fragment(); raise exception 'expired read accepted';
 exception when insufficient_privilege then null; end;
 begin perform qr_attendance_private.set_master_feature_with_proof(true,'fixture-bound-proof'); raise exception 'expired write accepted';
 exception when insufficient_privilege then null; end;
end $$;
