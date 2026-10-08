-- Synthetic identities only. Production company configurations are never migrated.
insert into company_members values
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','owner');
insert into company_members values
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000012','viewer'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000013','viewer'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000014','manager'),
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000021','owner');
insert into workers values('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000013','worker');
select set_config('test.actor','00000000-0000-0000-0000-000000000011',false);
do $$ begin
 if (select count(*) from worker_personnel_approvers where company_id='00000000-0000-0000-0000-000000000001')<>1 then raise exception 'initial default is not one'; end if;
 if not exists(select 1 from public.company_approval_assignee_rows() where role='viewer') then raise exception 'daily viewer candidate absent'; end if;
 if not (public.worker_personnel_approver_rows()->'candidates' @> '[{"role":"viewer"}]'::jsonb) then raise exception 'personnel viewer candidate absent'; end if;
end $$;
select public.set_worker_personnel_approvers(array['00000000-0000-0000-0000-000000000012'::uuid]);
select public.set_company_approval_assignee('00000000-0000-0000-0000-000000000012',true);
insert into daily_report_edit_requests values('00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','pending',1,null);
insert into worker_personnel_change_requests(id,company_id,worker_id,requested_by,proposed,status,required_approvals) values
 ('00000000-0000-0000-0000-000000000042','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000011','{"name":"updated"}','pending',1);
select set_config('test.actor','00000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$ begin
 if (select count(*) from daily_report_edit_requests)<>1 then raise exception 'selected viewer cannot read target'; end if;
 if jsonb_array_length(public.pending_worker_personnel_changes())<>1 then raise exception 'selected personnel viewer cannot read target'; end if;
 if public.decide_daily_report_edit('00000000-0000-0000-0000-000000000041','approve')<>'approved' then raise exception 'one daily approver did not complete'; end if;
 if public.decide_worker_personnel_change('00000000-0000-0000-0000-000000000042',true)->>'status'<>'approved' then raise exception 'one personnel approver did not complete'; end if;
 begin perform public.set_worker_personnel_approvers(array['00000000-0000-0000-0000-000000000012'::uuid]); raise exception 'viewer gained settings access';
 exception when raise_exception then if sqlerrm='viewer gained settings access' then raise; end if; end;
end $$;
reset role;
insert into daily_report_edit_requests values('00000000-0000-0000-0000-000000000043','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','pending',1,null);
insert into worker_personnel_change_requests(id,company_id,worker_id,requested_by,proposed,status,required_approvals) values
 ('00000000-0000-0000-0000-000000000044','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000011','{}','pending',1);
-- An unselected colleague and a different company's owner cannot read or decide.
select set_config('test.actor','00000000-0000-0000-0000-000000000013',false);
set role authenticated;
do $$ begin
 if exists(select 1 from daily_report_edit_requests) then raise exception 'unselected viewer read target'; end if;
 if jsonb_array_length(public.pending_worker_personnel_changes())<>0 then raise exception 'unselected viewer read personnel'; end if;
 begin perform public.decide_daily_report_edit('00000000-0000-0000-0000-000000000043','approve'); raise exception 'unselected viewer approved';
 exception when raise_exception then if sqlerrm='unselected viewer approved' then raise; end if; end;
 begin perform public.decide_worker_personnel_change('00000000-0000-0000-0000-000000000044',true); raise exception 'unselected viewer approved personnel';
 exception when raise_exception then if sqlerrm='unselected viewer approved personnel' then raise; end if; end;
end $$;
select set_config('test.actor','00000000-0000-0000-0000-000000000021',false);
do $$ begin
 if exists(select 1 from daily_report_edit_requests) then raise exception 'foreign owner read target'; end if;
 begin perform public.decide_daily_report_edit('00000000-0000-0000-0000-000000000043','approve'); raise exception 'foreign owner approved';
 exception when raise_exception then if sqlerrm='foreign owner approved' then raise; end if; end;
end $$;
reset role;
-- Existing 3-person configuration survives further member registration.
select set_config('test.actor','00000000-0000-0000-0000-000000000011',false);
select public.set_worker_personnel_approvers(array['00000000-0000-0000-0000-000000000011'::uuid,'00000000-0000-0000-0000-000000000012'::uuid,'00000000-0000-0000-0000-000000000014'::uuid]);
insert into company_members values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000015','admin');
do $$ begin
 if (select count(*) from worker_personnel_approvers where company_id='00000000-0000-0000-0000-000000000001')<>3 then raise exception 'existing three-person configuration shrunk'; end if;
 begin perform public.set_worker_personnel_approvers(array[]::uuid[]); raise exception 'zero accepted';
 exception when raise_exception then if sqlerrm='zero accepted' then raise; end if; end;
 begin perform public.set_worker_personnel_approvers(array['00000000-0000-0000-0000-000000000011'::uuid,'00000000-0000-0000-0000-000000000012'::uuid,'00000000-0000-0000-0000-000000000014'::uuid,'00000000-0000-0000-0000-000000000015'::uuid]); raise exception 'four accepted';
 exception when raise_exception then if sqlerrm='four accepted' then raise; end if; end;
 begin perform public.set_worker_personnel_approvers(array['00000000-0000-0000-0000-000000000021'::uuid]); raise exception 'foreign candidate accepted';
 exception when raise_exception then if sqlerrm='foreign candidate accepted' then raise; end if; end;
end $$;

-- Saving viewer permissions preserves approval assignment without broad management flags.
select public.set_member_feature_permissions('00000000-0000-0000-0000-000000000012','viewer','{}');
do $$ begin
 if not exists(select 1 from company_approval_assignees where user_id='00000000-0000-0000-0000-000000000012') then raise exception 'permission save removed viewer assignment'; end if;
 if exists(select 1 from member_feature_permissions where user_id='00000000-0000-0000-0000-000000000012' and (can_manage_people or can_manage_attendance or can_manage_payroll or can_manage_invoices or can_manage_vehicles or can_manage_routes)) then raise exception 'assignment gained management flags'; end if;
end $$;
-- A previously selected member who leaves the company loses approval access.
delete from company_members where user_id='00000000-0000-0000-0000-000000000012';
select set_config('test.actor','00000000-0000-0000-0000-000000000012',false);
set role authenticated;
do $$ begin
 if private.is_company_approval_assignee('00000000-0000-0000-0000-000000000001') or private.is_worker_personnel_approver('00000000-0000-0000-0000-000000000001') then raise exception 'departed assignee remained eligible'; end if;
end $$;
reset role;
select set_config('test.actor','00000000-0000-0000-0000-000000000011',false);
select set_config('test.blocked','true',false);
set role authenticated;
do $$ begin
 if private.is_worker_personnel_approver('00000000-0000-0000-0000-000000000001') then raise exception 'blocked account remained eligible'; end if;
 begin perform public.worker_personnel_approver_rows(); raise exception 'blocked account read settings';
 exception when raise_exception then if sqlerrm='blocked account read settings' then raise; end if; end;
end $$;
reset role;
