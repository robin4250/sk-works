-- Synthetic access prerequisites matching the verified live helper semantics.
-- Never replaces a real helper or runs against a linked DB.
create table public.payroll_access(company_id uuid,user_id uuid,can_view boolean,can_edit boolean);
insert into public.payroll_access values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',true,true),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003',true,false);
create function private.payroll_allowed(cid uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.company_members cm where cm.company_id=cid and cm.user_id=auth.uid()) and
 (private.has_company_feature(cid,'can_manage_payroll') or exists(select 1 from public.payroll_access a where a.company_id=cid and a.user_id=auth.uid() and
  case when cap='edit' then a.can_edit when cap='view' then a.can_view or a.can_edit else false end))
$$;
create function private.payroll_settings_allowed(cid uuid,wid uuid,cap text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.payroll_allowed(cid,cap) and exists(select 1 from public.workers w where w.id=wid and w.company_id=cid)
$$;

-- Match the live payroll workflow vocabulary; no synthetic approved state.
alter table public.payroll_statements add constraint fixture_payroll_workflow_state check(workflow_state in ('legacy','draft','finalized'));
