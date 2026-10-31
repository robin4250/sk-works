-- Catalog only. Runtime object identifiers are replaced with stable type/role names.
with ns as(select oid,nspname from pg_namespace where nspname=any($1::text[])),
funcs as(select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
 (to_jsonb(p)-array['oid','pronamespace','proowner','prolang','prorettype','proargtypes','proallargtypes','proargdefaults','prosqlbody','prosupport','protrftypes','prosrc','proacl'])||
 jsonb_build_object('namespace',n.nspname,'owner',pg_get_userbyid(p.proowner),'language',l.lanname,'result_type',format_type(p.prorettype,null),
 'arg_types',(select jsonb_agg(format_type(t,null) order by ord) from unnest(p.proargtypes)with ordinality a(t,ord)),
 'all_arg_types',(select jsonb_agg(format_type(t,null) order by ord) from unnest(p.proallargtypes)with ordinality a(t,ord)),
 'arg_defaults',pg_get_expr(p.proargdefaults,0),'sql_body_present',p.prosqlbody is not null,
 'support',case when p.prosupport=0 then null else p.prosupport::regprocedure::text end,'source_md5',md5(p.prosrc),
 'acl',(select jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,a.is_grantable)order by case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,pg_get_userbyid(a.grantor))
 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a)) attrs
 from pg_proc p join ns n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang),
rels as(select c.oid,n.nspname||'.'||c.relname identity,
 (to_jsonb(c)-array['oid','relnamespace','reltype','reloftype','relowner','relam','relfilenode','reltablespace','reltoastrelid','relacl','relpages','reltuples','relallvisible','relallfrozen','relfrozenxid','relminmxid','relrewrite'])||jsonb_build_object(
 'owner',pg_get_userbyid(c.relowner),'type',case when c.reltype=0 then null else format_type(c.reltype,null)end,
 'of_type',case when c.reloftype=0 then null else format_type(c.reloftype,null)end,
 'access_method',(select amname from pg_am where oid=c.relam),'tablespace',(select spcname from pg_tablespace where oid=c.reltablespace),
 'toast_present',c.reltoastrelid<>0,
 'columns',(select jsonb_agg((to_jsonb(a)-array['attrelid','atttypid','attcollation'])||jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'collation',(select coalesce(n2.nspname||'.','')||co.collname from pg_collation co join pg_namespace n2 on n2.oid=co.collnamespace where co.oid=a.attcollation))order by a.attnum)from pg_attribute a where a.attrelid=c.oid),
 'defaults',(select jsonb_agg(jsonb_build_object('column',adnum,'expression',pg_get_expr(adbin,adrelid))order by adnum)from pg_attrdef where adrelid=c.oid),
 'constraints',(select jsonb_agg(jsonb_build_object('name',conname,'type',contype,'deferrable',condeferrable,'deferred',condeferred,'validated',convalidated,'definition',pg_get_constraintdef(oid,true))order by conname)from pg_constraint where conrelid=c.oid),
 'indexes',(select jsonb_agg(jsonb_build_object('name',ic.relname,'attrs',to_jsonb(i)-array['indexrelid','indrelid','indclass','indcollation','indexprs','indpred'],'definition',pg_get_indexdef(i.indexrelid))order by ic.relname)from pg_index i join pg_class ic on ic.oid=i.indexrelid where i.indrelid=c.oid),
 'triggers',(select jsonb_agg(jsonb_build_object(
 'name',case when t.tgisinternal and t.tgconstraint<>0 then 'internal:'||kn.nspname||'.'||k.conname||':'||t.tgtype else t.tgname::text end,
 'attrs',to_jsonb(t)-array['oid','tgname','tgrelid','tgparentid','tgfoid','tgconstrrelid','tgconstrindid','tgconstraint','tgqual'],
 'definition',case when t.tgisinternal then null else pg_get_triggerdef(t.oid,true)end,'function',t.tgfoid::regprocedure::text,
 'constraint',case when k.oid is null then null else kn.nspname||'.'||k.conname end,
 'constraint_relation',case when t.tgconstrrelid=0 then null else t.tgconstrrelid::regclass::text end,
 'constraint_index',case when t.tgconstrindid=0 then null else t.tgconstrindid::regclass::text end,
 'qualification',pg_get_expr(t.tgqual,t.tgrelid))order by case when t.tgisinternal and t.tgconstraint<>0 then 'internal:'||kn.nspname||'.'||k.conname||':'||t.tgtype else t.tgname::text end)
 from pg_trigger t left join pg_constraint k on k.oid=t.tgconstraint left join pg_namespace kn on kn.oid=k.connamespace where t.tgrelid=c.oid),
 'policies',(select jsonb_agg(jsonb_build_object('name',polname,'command',polcmd,'permissive',polpermissive,
 'roles',(select jsonb_agg(case when role=0 then 'PUBLIC' else pg_get_userbyid(role)end order by role)from unnest(polroles)role),
 'using',pg_get_expr(polqual,polrelid),'check',pg_get_expr(polwithcheck,polrelid))order by polname)from pg_policy where polrelid=c.oid),
 'acl',(select jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,a.is_grantable)order by case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,pg_get_userbyid(a.grantor))
 from aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner)))a)) attrs
 from pg_class c join ns n on n.oid=c.relnamespace)
select jsonb_build_object(
 'namespaces',(select jsonb_agg(jsonb_build_object('name',n.nspname,'owner',pg_get_userbyid(p.nspowner),
 'acl',(select jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,a.is_grantable)order by case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,pg_get_userbyid(a.grantor))from aclexplode(coalesce(p.nspacl,acldefault('n',p.nspowner)))a))order by n.nspname)from ns n join pg_namespace p on p.oid=n.oid),
 'functions',(select jsonb_object_agg(identity,attrs order by identity)from funcs where split_part(identity,'(',1)=any(array['auth.jwt','auth.uid','private.account_access_allowed','private.document_company_seal_snapshot','private.require_reauthentication_session','private.account_deletion_barrier_key','private.aoyagi_reisho_name_supported','private.uploaded_company_seal_snapshot','private.require_trade_documents_master_feature','private.require_standalone_trade_document_access','private.standalone_trade_document_registration_context','private.respond_site_share','public.respond_site_share'])),
 'relations',(select jsonb_object_agg(identity,attrs order by identity)from rels where identity=any(array['auth.sessions','auth.users','private.account_deletion_access_restrictions','private.company_connections','private.company_seal_png_selection','private.company_seal_png_versions','public.companies','public.company_members','public.trade_companies','private.master_feature_settings','private.document_deliveries','private.company_data_delivery_items','private.site_share_inbox','public.sites','public.app_notifications'])),
 'default_acls',(select jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'namespace',case when d.defaclnamespace=0 then null else d.defaclnamespace::regnamespace::text end,'object_type',d.defaclobjtype,'acl',(select jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,a.is_grantable)order by case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,a.privilege_type,pg_get_userbyid(a.grantor))from aclexplode(d.defaclacl)a))order by pg_get_userbyid(d.defaclrole),coalesce(d.defaclnamespace::regnamespace::text,''),d.defaclobjtype)from pg_default_acl d))v;
