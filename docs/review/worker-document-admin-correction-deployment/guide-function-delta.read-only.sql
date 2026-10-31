-- READ ONLY, only after an approved guide installation has committed.
-- Capture alongside the complete before/after document catalog, never a RPC.
select p.oid,n.nspname,p.proname,p.proargtypes::text args,
 pg_get_userbyid(p.proowner) owner,l.lanname,
 encode(sha256(convert_to((to_jsonb(p)-'oid')::text,'UTF8')),'hex') attributes_sha256,
 encode(sha256(convert_to(coalesce(obj_description(p.oid,'pg_proc'),''),'UTF8')),'hex') comment_sha256,
 (to_jsonb(p)-array['oid','pronamespace','proowner','prolang','prosrc'])||jsonb_build_object('body_md5',md5(p.prosrc)) catalog,
 (select jsonb_agg(jsonb_build_object('role',case when a.grantee=0 then 'PUBLIC' else a.grantee::regrole::text end,
  'grantor',a.grantor::regrole::text,'privilege',a.privilege_type,'grant_option',a.is_grantable)
  order by case when a.grantee=0 then 'PUBLIC' else a.grantee::regrole::text end)
 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a) acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
where n.nspname in('private','public') and p.proname='current_user_required_document_attention_for_company'
order by n.nspname,p.oid;
