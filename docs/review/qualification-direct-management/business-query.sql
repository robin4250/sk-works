select md5(jsonb_build_object(
 'qualifications',(select jsonb_agg(to_jsonb(q) order by id) from public.worker_qualifications q),
 'official_history',(select jsonb_agg(to_jsonb(q) order by id) from private.worker_qualification_history q),
 'photo_history',(select jsonb_agg(to_jsonb(q) order by id) from private.qualification_photo_history q),
 'submissions',(select jsonb_agg(to_jsonb(q) order by id) from private.qualification_submissions q),
 'workers',(select jsonb_agg(to_jsonb(q) order by id) from public.workers q),
 'master',(select jsonb_agg(to_jsonb(q) order by id) from public.qualification_master q),
 'members',(select jsonb_agg(to_jsonb(q) order by company_id,user_id) from public.company_members q),
 'member_permissions',(select jsonb_agg(to_jsonb(q) order by company_id,user_id) from public.member_feature_permissions q)
)::text) business_md5;
