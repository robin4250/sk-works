-- READ ONLY. Aggregate state and catalog only; no personal document data.
select jsonb_build_object(
 'schema',1,
 'module_state',jsonb_build_object(
   'settings_count',(select count(*) from private.worker_document_exemption_settings),
   'enabled',(select enabled from private.worker_document_exemption_settings where singleton),
   'decision_count',(select count(*) from private.worker_document_exemptions),
   'event_count',(select count(*) from private.worker_document_exemption_events)),
 'functions',(select jsonb_object_agg(f.name,jsonb_build_object(
   'exists',p.oid is not null,'body_md5',md5(p.prosrc),
   'attrs_md5',md5((to_jsonb(p)-array['prosrc','probin','oid'])::text),
   'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text))
  from (values ('public.current_user_required_document_attention()'),
   ('private.require_reauthentication_session()'),('private.account_access_allowed()'),
   ('private.worker_document_exemption(text,jsonb)'),('public.worker_document_exemption(text,jsonb)')) f(name)
  left join pg_proc p on p.oid=to_regprocedure(f.name)),
 'relations',(select jsonb_object_agg(r.name,jsonb_build_object(
   'exists',c.oid is not null,'owner',pg_get_userbyid(c.relowner),'kind',c.relkind,
   'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
   'reloptions',c.reloptions,'persistence',c.relpersistence,'replica_identity',c.relreplident,
   'defaults',(select coalesce(jsonb_agg(jsonb_build_object('column',a.attname,'expression',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]'::jsonb) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where d.adrelid=c.oid),
   'indexes',(select coalesce(jsonb_agg(jsonb_build_object('name',ic.relname,'definition',pg_get_indexdef(i.indexrelid),'index_attrs',to_jsonb(i)-array['indexrelid','indrelid'],'index_options',ic.reloptions,'index_acl',ic.relacl::text,'index_owner',pg_get_userbyid(ic.relowner)) order by ic.relname),'[]'::jsonb) from pg_index i join pg_class ic on ic.oid=i.indexrelid where i.indrelid=c.oid),
   'sequence',(select jsonb_build_object('seqtypid',s.seqtypid,'seqstart',s.seqstart::text,'seqincrement',s.seqincrement::text,'seqmax',s.seqmax::text,'seqmin',s.seqmin::text,'seqcache',s.seqcache::text,'seqcycle',s.seqcycle) from pg_sequence s where s.seqrelid=c.oid),
   'columns',(select coalesce(jsonb_agg(to_jsonb(a)-array['attrelid'] order by a.attnum),'[]'::jsonb) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',k.conname,'definition',pg_get_constraintdef(k.oid),'type',k.contype,'validated',k.convalidated) order by k.conname),'[]'::jsonb) from pg_constraint k where k.conrelid=c.oid),
   'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled,'internal',t.tgisinternal) order by t.tgname),'[]'::jsonb) from pg_trigger t where t.tgrelid=c.oid),
   'policies',(select coalesce(jsonb_agg(to_jsonb(k)-array['oid','polrelid'] order by k.polname),'[]'::jsonb) from pg_policy k where k.polrelid=c.oid)))
  from(values ('private.worker_document_exemption_settings'),('private.worker_document_exemptions'),('private.worker_document_exemption_events'),('private.worker_document_exemption_events_id_seq')) r(name)
  left join pg_class c on c.oid=to_regclass(r.name)),
 'private_schema',(select jsonb_build_object('owner',pg_get_userbyid(nspowner),'acl',nspacl::text) from pg_namespace where nspname='private'),
 'defaults',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',coalesce(n.nspname,''),'type',d.defaclobjtype,'acl',d.defaclacl::text) order by d.defaclrole,d.defaclnamespace,d.defaclobjtype),'[]'::jsonb) from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace)
) as snapshot;
