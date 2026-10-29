-- Union of existing manager ALL and people-feature ALL policies, with account gate.
create function private.worker_document_change_can_manage(cid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed() and (
 private.has_company_feature(cid,'can_manage_people') or exists(
 select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid()
 and m.role::text in ('owner','admin','manager'))) $$;
revoke all on function private.worker_document_change_can_manage(uuid) from public,anon,authenticated,service_role;
create function private.worker_document_change_can_review(cid uuid) returns boolean
language sql stable security definer set search_path='' as $$select private.worker_document_change_can_manage(cid)$$;
revoke all on function private.worker_document_change_can_review(uuid) from public,anon,authenticated,service_role;
