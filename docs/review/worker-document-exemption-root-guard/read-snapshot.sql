-- Read-only catalog and complete row hashes. No personal row content is returned.
select jsonb_build_object(
 'schema',1,
 'functions',(select jsonb_object_agg(f.name,jsonb_build_object(
   'exists',p.oid is not null,'definition',pg_get_functiondef(p.oid),
   'body_md5',md5(p.prosrc),'attrs_md5',md5((to_jsonb(p)-array['prosrc','probin','oid'])::text),
   'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text))
  from (values ('public.current_user_required_document_attention()'),
   ('private.require_reauthentication_session()'),('private.account_access_allowed()'),
   ('private.worker_document_exemption(text,jsonb)'),('public.worker_document_exemption(text,jsonb)')) f(name)
  left join pg_proc p on p.oid=to_regprocedure(f.name)),
 'business',jsonb_build_object(
  'public.companies',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.companies t),
  'public.company_members',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.company_members t),
  'public.workers',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.workers t),
  'public.document_requirements',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.document_requirements t),
  'public.worker_document_statuses',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.worker_document_statuses t),
  'public.worker_document_status_history',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.worker_document_status_history t),
  'public.worker_private_bank_accounts',(select jsonb_build_object('count',count(*),'md5',md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text)) from public.worker_private_bank_accounts t)
 ),
 'new_tables',(select jsonb_object_agg(r.name,to_regclass(r.name) is not null) from(values
  ('private.worker_document_exemption_settings'),('private.worker_document_exemptions'),('private.worker_document_exemption_events')) r(name))
) as snapshot;
