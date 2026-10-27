\set ON_ERROR_STOP on
create schema private; create schema auth;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select true$$;
create function public.is_current_user_master_admin() returns boolean language sql as $$select current_setting('test.master',true)='yes'$$;
create function private.require_reauthentication_session() returns uuid language plpgsql as $$begin if current_setting('test.session',true) is distinct from 'yes' then raise sqlstate '42501';end if;return '00000000-0000-0000-0000-000000000002';end$$;
create function private.reauthentication_required(text) returns boolean language sql as $$select false$$;
create function private.consume_reauthentication_proof(text,jsonb,text) returns void language plpgsql as $$begin if not public.is_current_user_master_admin() then raise sqlstate '42501';end if;end$$;
create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid, constraint master_feature_settings_feature_key_check check(feature_key in('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')));
\i extension.sql.review-only
\i operation-guard.sql.review-only
\i change-audit.sql.review-only
set test.session='yes'; set test.master='yes';
do $$begin
 assert public.current_master_feature_flags()->>'vehicle_management'='true';
 assert public.current_master_feature_flags()->>'affiliation_switch'='false';
 begin perform private.require_lifecycle_features(array['affiliation_switch']);raise exception 'OFF accepted';exception when insufficient_privilege then null;end;
 perform public.set_master_feature_enabled('affiliation_switch',true);
 perform private.require_lifecycle_features(array['affiliation_switch']);
 assert (select count(*) from private.lifecycle_feature_audit)=1;
 begin perform private.require_lifecycle_features(array['affiliation_switch','personal_pdf_vault']);raise exception 'missing dependency accepted';exception when insufficient_privilege then null;end;
 perform public.set_master_feature_enabled_with_proof('affiliation_switch',false,'synthetic');
 assert (select count(*) from private.lifecycle_feature_audit)=2;
 assert (select count(*) from private.master_feature_settings where feature_key in('affiliation_switch','sko_id_linking','personal_pdf_vault','partner_auto_link','company_lifecycle'))=5;
 begin delete from private.master_feature_settings where feature_key='affiliation_switch';raise exception 'delete accepted';exception when insufficient_privilege then null;end;
 perform set_config('test.master','no',false);
 begin perform public.set_master_feature_enabled('affiliation_switch',true);raise exception 'nonmaster accepted';exception when insufficient_privilege then null;end;
 perform set_config('test.master','yes',false);perform set_config('test.session','no',false);
 begin perform public.set_master_feature_enabled('affiliation_switch',true);raise exception 'stale session accepted';exception when insufficient_privilege then null;end;
 assert not has_function_privilege('authenticated','private.require_lifecycle_features(text[])','execute');
end$$;
