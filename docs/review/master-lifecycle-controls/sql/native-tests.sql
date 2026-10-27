\set ON_ERROR_STOP on
-- Real session/Master function bodies, synthetic Auth tables and signed-claim stand-ins.
\i restore-unused.sql.review-only
do $$begin
 assert to_regprocedure('private.require_lifecycle_features(text[])') is null;
 assert (select count(*) from private.master_feature_settings)=0;
end$$;
\i extension.sql.review-only
\i operation-guard.sql.review-only
\i change-audit.sql.review-only
insert into auth.users values('00000000-0000-0000-0000-000000000001',false,null),('00000000-0000-0000-0000-000000000009',false,null);
insert into auth.sessions values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',null),('00000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000009',null);
insert into private.master_admins values('00000000-0000-0000-0000-000000000001',true);
insert into public.company_members values('00000000-0000-0000-0000-000000000009','admin','00000000-0000-0000-0000-000000000007');
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
do $$declare i int; begin
 perform public.set_master_feature_enabled('affiliation_switch',true);
 perform private.require_lifecycle_features(array['affiliation_switch']);
 perform set_config('test.actor','00000000-0000-0000-0000-000000000009',false);
 perform set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000008","is_anonymous":false}',false);
 begin perform public.set_master_feature_enabled('affiliation_switch',false);raise exception 'company admin allowed';exception when insufficient_privilege then null;end;
 perform set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
 -- foreign-user session, unknown/missing session, anonymous claims and bad role.
 for i in 1..5 loop
   perform set_config('test.jwt',case i
     when 1 then '{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000008"}'
     when 2 then '{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000099"}'
     when 3 then '{"role":"authenticated"}'
     when 4 then '{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":true}'
     else '{"role":"anon","session_id":"00000000-0000-0000-0000-000000000002"}' end,false);
   begin perform public.set_master_feature_enabled('affiliation_switch',false);raise exception 'bad session allowed';exception when insufficient_privilege then null;end;
 end loop;
 perform set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
 update auth.sessions set not_after=now()-interval '1 second' where user_id=auth.uid();
 begin perform private.require_lifecycle_features(array['affiliation_switch']);raise exception 'expired allowed';exception when insufficient_privilege then null;end;
 update auth.sessions set not_after=null;
 update auth.users set banned_until=now()+interval '1 day' where id=auth.uid();
 begin perform public.set_master_feature_enabled('affiliation_switch',false);raise exception 'banned allowed';exception when insufficient_privilege then null;end;
 update auth.users set banned_until=null;
 insert into private.account_deletion_access_restrictions values(auth.uid());
 begin perform public.set_master_feature_enabled('affiliation_switch',false);raise exception 'restricted allowed';exception when insufficient_privilege then null;end;
 delete from private.account_deletion_access_restrictions;
 assert (select count(*) from private.lifecycle_feature_audit)=1;
end$$;
