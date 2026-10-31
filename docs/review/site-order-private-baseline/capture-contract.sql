-- READ ONLY catalog evidence. No business rows, secrets, or function invocation.
begin read only;
set local statement_timeout='15s';
with requested(signature) as (values
 ('auth.uid()'),('auth.jwt()'),('private.account_access_allowed()'),
 ('private.require_reauthentication_session()'),('private.account_deletion_barrier_key(uuid)'),
 ('private.document_company_seal_snapshot(jsonb,uuid,boolean)'),
 ('private.uploaded_company_seal_snapshot(uuid)'),('private.aoyagi_reisho_name_supported(text)')),
rels as (select n.nspname||'.'||c.relname name,c.* from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname||'.'||c.relname in('auth.users','auth.sessions','public.companies','public.company_members','public.trade_companies',
 'private.account_deletion_access_restrictions','private.company_connections','private.company_seal_png_selection','private.company_seal_png_versions')),
funcs as (select r.signature,p.* from requested r left join pg_proc p on p.oid=to_regprocedure(r.signature))
select jsonb_build_object(
 'server_version_num',current_setting('server_version_num'),
 'functions',(select jsonb_agg(jsonb_build_object('signature',f.signature,'body_md5',md5(f.prosrc),
 'owner',pg_get_userbyid(f.proowner),'attrs',to_jsonb(f),
 'acl',(select jsonb_agg(jsonb_build_object('grantor',pg_get_userbyid(a.grantor),'grantee',case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end,
 'privilege',a.privilege_type,'grant_option',a.is_grantable) order by a.grantee,a.privilege_type)
 from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a)) order by f.signature) from funcs f),
 'relations',(select jsonb_agg(jsonb_build_object('name',r.name,'attrs',to_jsonb(r),
 'columns',(select jsonb_agg(to_jsonb(a) order by a.attnum) from pg_attribute a where a.attrelid=r.oid),
 'defaults',(select jsonb_agg(to_jsonb(d)||jsonb_build_object('expression',pg_get_expr(d.adbin,d.adrelid)) order by d.adnum) from pg_attrdef d where d.adrelid=r.oid),
 'constraints',(select jsonb_agg(to_jsonb(k)||jsonb_build_object('definition',pg_get_constraintdef(k.oid,true)) order by k.oid) from pg_constraint k where k.conrelid=r.oid),
 'indexes',(select jsonb_agg(to_jsonb(i)||jsonb_build_object('definition',pg_get_indexdef(i.indexrelid)) order by i.indexrelid) from pg_index i where i.indrelid=r.oid),
 'triggers',(select jsonb_agg(to_jsonb(t)||jsonb_build_object('definition',pg_get_triggerdef(t.oid,true)) order by t.oid) from pg_trigger t where t.tgrelid=r.oid),
 'policies',(select jsonb_agg(to_jsonb(p) order by p.oid) from pg_policy p where p.polrelid=r.oid)) order by r.name) from rels r),
 'default_acls',(select jsonb_agg(to_jsonb(d) order by d.oid) from pg_default_acl d),
 'new_namespace_presence',(select jsonb_agg(nspname order by nspname) from pg_namespace where nspname in('trade_document_consent_private','trade_document_confirmation_api_private')));
rollback;
