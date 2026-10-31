-- Catalog and fixed document-bucket configuration only; no application document rows. Run under the deployment role.
with target(name) as (values
 ('public.companies'),('public.company_members'),('public.member_feature_permissions'),
 ('public.company_approval_assignees'),('public.workers'),('public.document_requirements'),
 ('public.worker_document_statuses'),('public.worker_document_status_history'),
 ('private.account_deletion_access_restrictions'),('auth.users'),('auth.sessions'),('storage.objects')),
rels as (select name,to_regclass(name) oid from target),
fn as (select p.oid,n.nspname,p.proname,p.proargtypes::text args,
 encode(sha256(convert_to((to_jsonb(p)-'oid')::text,'UTF8')),'hex') attributes_sha256,
 encode(sha256(convert_to(coalesce(obj_description(p.oid,'pg_proc'),''),'UTF8')),'hex') comment_sha256
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('public','private','auth','storage')
 and not ((n.nspname='private' and p.proname in
 ('worker_document_admin_correction_immutable','worker_document_admin_correction_retains','worker_document_admin_correction_ticket_guard'))
 or(n.nspname='public' and p.proname='worker_document_admin_self_correction'))),
relation_values as (select r.name,r.oid is not null as present,
 jsonb_build_object('class',to_jsonb(c)-array['oid','relfilenode','relpages','reltuples','relallvisible','relfrozenxid','relminmxid'],
 'columns',(select jsonb_agg(to_jsonb(a)-'attrelid' order by a.attnum) from pg_attribute a where a.attrelid=r.oid and a.attnum>0),
 'defaults',(select jsonb_agg(to_jsonb(d)-array['oid','adrelid'] order by d.adnum) from pg_attrdef d where d.adrelid=r.oid),
 'constraints',(select jsonb_agg(to_jsonb(q)-'oid' order by q.conname) from pg_constraint q where q.conrelid=r.oid),
 'indexes',(select jsonb_agg(to_jsonb(i) order by i.indexrelid) from pg_index i where i.indrelid=r.oid),
 'owned_sequences',(select jsonb_agg(jsonb_build_object('class',to_jsonb(sc)-array['oid','relfilenode','relpages','reltuples','relallvisible','relfrozenxid','relminmxid'],'sequence',to_jsonb(s)||jsonb_build_object('seqstart',s.seqstart::text,'seqincrement',s.seqincrement::text,'seqmax',s.seqmax::text,'seqmin',s.seqmin::text,'seqcache',s.seqcache::text)) order by s.seqrelid) from pg_sequence s join pg_class sc on sc.oid=s.seqrelid join pg_depend d on d.classid='pg_class'::regclass and d.objid=s.seqrelid and d.refobjid=r.oid and d.deptype in('a','i')),
 'triggers',(select jsonb_agg(to_jsonb(t)-'oid' order by t.tgname) from pg_trigger t where t.tgrelid=r.oid and not
  (r.name='public.worker_document_statuses' and t.tgname='zzz_worker_document_admin_correction_ticket')),
 'policies',(select jsonb_agg(to_jsonb(p)-'oid' order by p.polname) from pg_policy p where p.polrelid=r.oid and not (r.name='storage.objects' and p.polname in ('worker_document_admin_archive_no_overwrite','worker_document_admin_archive_no_delete'))),
 'comment',obj_description(r.oid,'pg_class')) as catalog
 from rels r left join pg_class c on c.oid=r.oid)
select jsonb_build_object(
 'version',1,
 'database_oid',(select oid from pg_database where datname=current_database()),
 'role',current_user,
 'functions',(select jsonb_agg(to_jsonb(fn) order by oid) from fn),
 'relations',(select jsonb_agg(to_jsonb(relation_values) order by name) from relation_values),
 'schemas',(select jsonb_agg(jsonb_build_object('name',nspname,'owner',nspowner,'acl',nspacl) order by nspname) from pg_namespace where nspname in('public','private','auth','storage')),
 'worker_document_bucket',(select jsonb_build_object('id',id,'public',public,'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types) from storage.buckets where id='worker-documents'),
 'role_authority',jsonb_build_object('roles',(select jsonb_agg(to_jsonb(r)-'rolpassword' order by oid) from pg_roles r where rolname in('postgres','anon','authenticated','service_role')),'memberships',(select jsonb_agg(to_jsonb(m) order by roleid,member,grantor) from pg_auth_members m)),
 'default_acls',(select jsonb_agg(to_jsonb(d)-'oid' order by defaclrole,defaclnamespace,defaclobjtype) from pg_default_acl d)
) as snapshot;
