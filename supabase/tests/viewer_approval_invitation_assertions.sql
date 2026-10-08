create function private.invite_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'assertion failed: %',label; end if; end $$;
create function private.expect_invite_denied(invite uuid,label text,expected text default 'onboarding approval permission required') returns void language plpgsql as $$
begin
 begin
  perform public.approve_employee_onboarding(invite);
 exception when others then
  if position(expected in SQLERRM)=0 then raise; end if;
  return;
 end;
 raise exception 'expected onboarding denial: %',label;
end $$;

insert into company_members values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','viewer'),
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','viewer');
insert into company_approval_assignees values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
insert into workers(id,company_id,name) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Viewer approver'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Plain viewer');
-- The new CHECK permits viewer + approval duty independently of management role.
insert into employee_registration_invites
 (id,company_id,auth_user_id,worker_id,status,requested_role,requested_approval_assignee,name,phone_e164) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000001','approval_pending','viewer',true,'Viewer approver','+819000000001'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000002','approval_pending','viewer',false,'Plain viewer','+819000000002');
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select public.approve_employee_onboarding('40000000-0000-0000-0000-000000000001');
select private.invite_assert((select role='viewer' from company_members where user_id='20000000-0000-0000-0000-000000000004'),'viewer role retained');
select private.invite_assert(not exists(select 1 from member_feature_permissions where user_id='20000000-0000-0000-0000-000000000004'),'no management permission rows created');
select set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
select private.invite_assert((public.current_feature_permissions()->>'can_approve_daily_report_edits')::boolean,'selected viewer has approval duty');
select private.invite_assert(not exists(select 1 from jsonb_each_text(public.current_feature_permissions()) p where p.key<>'can_approve_daily_report_edits' and p.value='true'),'selected viewer has no management features');
select set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
select private.expect_invite_denied('40000000-0000-0000-0000-000000000002','ordinary viewer');
select set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
select public.approve_employee_onboarding('40000000-0000-0000-0000-000000000002');
select private.invite_assert((select status='approved' from employee_registration_invites where id='40000000-0000-0000-0000-000000000002'),'currently selected viewer may approve onboarding');

-- Three selected approvers require an explicit, currently selected replacement.
insert into company_approval_assignees values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001');
insert into employee_registration_invites
 (id,company_id,auth_user_id,worker_id,status,requested_role,requested_approval_assignee,replace_approval_assignee_user_id,name,phone_e164) values
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000001','approval_pending','viewer',true,'20000000-0000-0000-0000-000000000004','Replacement','+819000000003'),
 ('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000007','30000000-0000-0000-0000-000000000002','approval_pending','viewer',true,null,'Over limit','+819000000004');
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select private.expect_invite_denied('40000000-0000-0000-0000-000000000004','limit without replacement','approval_assignee_limit_reached');
select private.invite_assert(not exists(select 1 from company_members where user_id='20000000-0000-0000-0000-000000000007'),'failed limit rolls back new membership');
select public.approve_employee_onboarding('40000000-0000-0000-0000-000000000003');
select private.invite_assert((select count(*)=3 from company_approval_assignees where company_id='10000000-0000-0000-0000-000000000001'),'replacement retains three-assignee cap');
select set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
select private.invite_assert(not (public.current_feature_permissions()->>'can_approve_daily_report_edits')::boolean,'removed viewer loses duty immediately');
select private.expect_invite_denied('40000000-0000-0000-0000-000000000004','removed assignee');

insert into employee_registration_invites
 (id,company_id,auth_user_id,worker_id,status,requested_role,requested_approval_assignee,name,phone_e164) values
 ('40000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000008','30000000-0000-0000-0000-000000000001','approval_pending','viewer',false,'Other company','+819000000005'),
 ('40000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000001','approval_pending','viewer',false,'Self','+819000000006');
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select private.expect_invite_denied('40000000-0000-0000-0000-000000000005','cross-company owner');
select set_config('test.actor','20000000-0000-0000-0000-000000000006',false);
select private.expect_invite_denied('40000000-0000-0000-0000-000000000006','self approval','employee cannot approve own onboarding');
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select set_config('test.blocked','true',false);
select private.expect_invite_denied('40000000-0000-0000-0000-000000000004','blocked account','authentication required');
select set_config('test.blocked','false',false);
select private.invite_assert(not exists(select 1 from member_feature_permissions),'no generic feature grants changed');
select private.invite_assert(not has_function_privilege('anon','public.approve_employee_onboarding(uuid)','EXECUTE'),'anon cannot approve');
