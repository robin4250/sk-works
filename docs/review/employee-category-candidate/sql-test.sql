select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select public.ensure_employee_categories('10000000-0000-0000-0000-000000000001');
select public.ensure_employee_categories('10000000-0000-0000-0000-000000000001');
do $$ declare cid uuid:='10000000-0000-0000-0000-000000000001'; wid uuid:='30000000-0000-0000-0000-000000000001'; category uuid; payload jsonb; result jsonb; begin
 assert (select count(*) from employee_category_private.categories where company_id=cid)=3, 'defaults must be idempotent';
 assert not exists(select 1 from employee_category_private.assignments), 'opening setup must not assign existing employees';
 select id into category from employee_category_private.categories where company_id=cid and name='正社員';
 perform private.apply_worker_personnel_payload(wid,jsonb_build_object('name','合成社員','family_members','[]'::jsonb),auth.uid());
 payload:=private.worker_personnel_payload(wid)||jsonb_build_object('employee_category_id',category);
 result:=public.save_worker_personnel_profile(wid,payload);
 assert result->>'status'='saved';
 assert (private.employee_personnel_view(cid)#>>'{records,0,employeeCategoryName}')='正社員';
 -- Old client omits the new field: no clearing and no change request.
 payload:=(private.worker_personnel_payload(wid)-'employee_category_id'-'employee_category_name');
 result:=public.save_worker_personnel_profile(wid,payload);
 assert result->>'status'='unchanged';
 assert (select category_id from employee_category_private.assignments where worker_id=wid)=category;
 payload:=payload || jsonb_build_object('department','合成部署');
 result:=public.save_worker_personnel_profile(wid,payload);
 assert result->>'status'='saved','existing field update failed';
 assert (select department from public.workers where id=wid)='合成部署';
 assert (select category_id from employee_category_private.assignments where worker_id=wid)=category,'category was cleared';
 begin
   perform public.add_employee_category('10000000-0000-0000-0000-000000000002','不正');
   raise exception 'cross-company write succeeded';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
select set_config('test.session','40000000-0000-0000-0000-000000000002',false);
do $$ declare cid uuid:='10000000-0000-0000-0000-000000000001'; wid uuid:='30000000-0000-0000-0000-000000000001'; category uuid; payload jsonb; result jsonb; begin
 select id into category from employee_category_private.categories where company_id=cid and name='派遣社員';
 payload:=private.worker_personnel_payload(wid)||jsonb_build_object('employee_category_id',category);
 result:=public.save_worker_personnel_profile(wid,payload);
 assert result->>'status'='pending';
 assert (private.employee_personnel_view(cid)#>>'{records,0,employeeCategoryName}')='正社員';
end $$;
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select set_config('test.session','40000000-0000-0000-0000-000000000001',false);
do $$ declare req uuid; r jsonb; begin
 select id into req from public.worker_personnel_change_requests where status='pending';
 r:=public.decide_worker_personnel_change(req,true);
 assert r->>'status'='approved';
 assert (private.employee_personnel_view('10000000-0000-0000-0000-000000000001')#>>'{records,0,employeeCategoryName}')='派遣社員';
end $$;

-- An archived category remains the employee's saved category; selecting a
-- different archived category must not revive it or silently clear the current one.
do $$ declare cid uuid:='10000000-0000-0000-0000-000000000001'; wid uuid:='30000000-0000-0000-0000-000000000001'; current_id uuid; other_id uuid; payload jsonb; result jsonb; before_audit bigint; begin
 select category_id into current_id from employee_category_private.assignments where worker_id=wid;
 select id into other_id from employee_category_private.categories where company_id=cid and name='アルバイト';
 update employee_category_private.categories set active=false where id in(current_id,other_id);
 select count(*) into before_audit from employee_category_private.audit;
 payload:=private.worker_personnel_payload(wid);
 result:=public.save_worker_personnel_profile(wid,payload);
 assert result->>'status'='unchanged','unchanged archived category rejected';
 assert (select category_id from employee_category_private.assignments where worker_id=wid)=current_id,'archived assignment lost';
 begin
  perform public.save_worker_personnel_profile(wid,payload||jsonb_build_object('employee_category_id',other_id));
  raise exception 'different archived category accepted';
 exception when raise_exception then
  if sqlerrm='different archived category accepted' then raise; end if;
 end;
 assert (select count(*) from employee_category_private.audit)=before_audit,'rejected category changed audit';
 assert (select category_id from employee_category_private.assignments where worker_id=wid)=current_id,'rejected category changed assignment';
 update employee_category_private.categories set active=true where id in(current_id,other_id);
end $$;

-- Real session helper: reject foreign, revoked, anonymous and banned sessions.
do $$ declare cid uuid:='10000000-0000-0000-0000-000000000001'; begin
 assert not has_function_privilege('anon','public.list_employee_categories(uuid)','execute');
 assert not has_function_privilege('anon','public.add_employee_category(uuid,text)','execute');
 perform set_config('test.session','40000000-0000-0000-0000-000000000002',true);
 begin perform public.list_employee_categories(cid); raise exception 'foreign session accepted'; exception when insufficient_privilege then null; end;
 perform set_config('test.session','40000000-0000-0000-0000-000000000001',true);
 perform set_config('test.anonymous','true',true);
 begin perform public.add_employee_category(cid,'不正'); raise exception 'anonymous accepted'; exception when insufficient_privilege then null; end;
 perform set_config('test.anonymous','false',true);
 update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=auth.uid();
 begin perform public.list_employee_categories(cid); raise exception 'banned accepted'; exception when insufficient_privilege then null; end;
 update auth.users set banned_until=null where id=auth.uid();
 delete from auth.sessions where id='40000000-0000-0000-0000-000000000001';
 begin perform public.list_employee_categories(cid); raise exception 'revoked accepted'; exception when insufficient_privilege then null; end;
end $$;
