\set ON_ERROR_STOP on
\i native-setup.sql
insert into auth.users values('00000000-0000-0000-0000-000000000001',false,null),('00000000-0000-0000-0000-000000000009',false,null);
insert into auth.sessions values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',null),('00000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000009',null);
insert into private.master_admins values('00000000-0000-0000-0000-000000000001',true);
select set_config('test.actor','00000000-0000-0000-0000-000000000001',false);
select set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}',false);
\i ../catalog.sql.review-only
do $$ begin
 begin perform personal_vault24_candidate.start_manifest('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',repeat('a',64),repeat('b',64),1);raise exception 'default OFF accepted';exception when insufficient_privilege then null;end;
end $$;
select public.set_master_feature_enabled('personal_pdf_vault',true);
do $$declare
 mid uuid:='10000000-0000-0000-0000-000000000001';cid uuid:='20000000-0000-0000-0000-000000000001';wid uuid:='30000000-0000-0000-0000-000000000001';rid uuid:='40000000-0000-0000-0000-000000000001';sid uuid:='50000000-0000-0000-0000-000000000001';a text:=repeat('a',64);b text:=repeat('b',64);path text;rows integer;
begin
 path:='personal-vault/'||auth.uid()::text||'/'||a||'.pdf';
 assert personal_vault24_candidate.start_manifest(mid,cid,wid,rid,a,b,1)=mid;
 assert personal_vault24_candidate.start_manifest('10000000-0000-0000-0000-000000000002',cid,wid,rid,a,b,1)=mid,'idempotent start';
 begin perform personal_vault24_candidate.start_manifest(mid,cid,wid,rid,a,a,1);raise exception 'test_expected_retry_conflict';exception when others then if sqlerrm='test_expected_retry_conflict' then raise;end if;end;
 begin perform personal_vault24_candidate.assert_transition_ready(mid,auth.uid(),cid,wid,rid,a);raise exception 'test_expected_pending';exception when others then if sqlerrm='test_expected_pending' then raise;end if;end;
 begin perform personal_vault24_candidate.seal_manifest(mid,array[a]);raise exception 'test_expected_missing';exception when others then if sqlerrm='test_expected_missing' then raise;end if;end;
 perform personal_vault24_candidate.record_item(mid,a,'own_payroll',sid,'r1',a,path,'v1',b,42);
 perform personal_vault24_candidate.record_item(mid,a,'own_payroll',sid,'r1',a,path,'v1',b,42);
 begin perform personal_vault24_candidate.record_item(mid,a,'own_payroll',sid,'r1',a,path,'v2',b,42);raise exception 'test_expected_no_overwrite';exception when others then if sqlerrm='test_expected_no_overwrite' then raise;end if;end;
 perform personal_vault24_candidate.seal_manifest(mid,array[a]);
 perform personal_vault24_candidate.seal_manifest(mid,array[a]);
 perform personal_vault24_candidate.assert_transition_ready(mid,auth.uid(),cid,wid,rid,a);
 begin perform personal_vault24_candidate.assert_transition_ready(mid,auth.uid(),cid,wid,rid,b);raise exception 'test_expected_snapshot_mismatch';exception when others then if sqlerrm='test_expected_snapshot_mismatch' then raise;end if;end;
 perform public.set_master_feature_enabled('personal_pdf_vault',false);
 select count(*) into rows from personal_vault24_candidate.list_mine();assert rows=1,'OFF preserves owned archive';
 select count(*) into rows from personal_vault24_candidate.item_for_owner(mid,a);assert rows=1;
 begin perform personal_vault24_candidate.seal_manifest(mid,array[a]);raise exception 'test_expected_off';exception when others then if sqlerrm='test_expected_off' then raise;end if;end;
 perform set_config('test.actor','00000000-0000-0000-0000-000000000009',true); perform set_config('test.jwt','{"role":"authenticated","session_id":"00000000-0000-0000-0000-000000000008"}',true);
 select count(*) into rows from personal_vault24_candidate.list_mine();assert rows=0,'other person cannot list';
 begin perform personal_vault24_candidate.item_for_owner(mid,a);raise exception 'test_expected_foreign';exception when others then if sqlerrm='test_expected_foreign' then raise;end if;end;
 update auth.sessions set not_after=now()-interval '1 second' where user_id=auth.uid();
 begin perform personal_vault24_candidate.list_mine();raise exception 'test_expected_expired';exception when others then if sqlerrm='test_expected_expired' then raise;end if;end;
 assert not has_function_privilege('authenticated','personal_vault24_candidate.record_item(uuid,text,text,uuid,text,text,text,text,text,bigint)','EXECUTE');
 assert not has_function_privilege('service_role','personal_vault24_candidate.record_item(uuid,text,text,uuid,text,text,text,text,text,bigint)','EXECUTE');
 assert (select count(*) from personal_vault24_candidate.items)=1;
end $$;
