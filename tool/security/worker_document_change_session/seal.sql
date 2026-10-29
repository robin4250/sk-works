-- No app/service direct access to request/ticket/event/rollout or private dispatcher.
revoke all on private.worker_document_changes,private.worker_document_apply_tickets from service_role;
create function private.worker_document_change_catalog() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef) order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and (p.proname like 'worker_document_change%' or p.oid in('private.require_reauthentication_session()'::regprocedure,'private.has_company_feature(uuid,text)'::regprocedure,'private.account_access_allowed()'::regprocedure))),
 'trigger',(select jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled)) from pg_trigger t where t.tgrelid='public.worker_document_statuses'::regclass and t.tgname='zz_worker_document_change_guard'),
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity) order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname in ('worker_document_changes','worker_document_apply_tickets','worker_document_change_events','worker_document_change_rollout','worker_document_change_installation')))
 $$;
revoke all on function private.worker_document_change_catalog() from public,anon,authenticated,service_role;
insert into private.worker_document_change_installation(catalog) select private.worker_document_change_catalog();
