\set ON_ERROR_STOP on
create schema private;
create role anon;
create role authenticated;
create table private.master_feature_settings(feature_key text primary key, enabled boolean not null);
create table private.fixture_devices(id int primary key);
insert into private.fixture_devices values(1);
\ir qr-master-gate.sql.review-only
do $$ begin
 begin perform qr_attendance_private.require_enabled(); raise exception 'missing row accepted';
 exception when insufficient_privilege then null; end;
end $$;
insert into private.master_feature_settings values('qr_attendance',true);
select qr_attendance_private.require_enabled();
update private.master_feature_settings set enabled=false where feature_key='qr_attendance';
do $$ begin
 begin perform qr_attendance_private.require_enabled(); raise exception 'disabled accepted';
 exception when insufficient_privilege then null; end;
 if (select count(*) from private.fixture_devices) <> 1 then raise exception 'device data changed'; end if;
end $$;
update private.master_feature_settings set enabled=true where feature_key='qr_attendance';
select qr_attendance_private.require_enabled();
