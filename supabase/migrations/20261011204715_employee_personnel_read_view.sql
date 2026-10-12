begin;
set local lock_timeout='5s';
-- Dedicated read scope. Existing profile writes, approvals and membership
-- permissions remain unchanged; viewer gains no management or export rights.
create function private.personnel_view_allowed(p_company uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.account_access_allowed()
 and exists(select 1 from public.company_members m
 where m.company_id=p_company and m.user_id=auth.uid()
 and (m.role::text in ('owner','admin','viewer')
 or (m.role::text='manager' and private.has_company_feature(p_company,'can_manage_people'))));
$$;
revoke all on function private.personnel_view_allowed(uuid) from public,anon;
grant execute on function private.personnel_view_allowed(uuid) to authenticated;

create function private.personnel_portrait_path(p_company uuid,p_worker uuid)
returns text language plpgsql stable security definer set search_path='' as $$
begin
 if not private.personnel_view_allowed(p_company) then return null; end if;
 return (select s.attachment_path from public.worker_document_statuses s
 join public.document_requirements r on r.id=s.requirement_id and r.company_id=s.company_id
 join public.workers w on w.id=s.worker_id and w.company_id=s.company_id
 where s.company_id=p_company and s.worker_id=p_worker and r.is_active
 and regexp_replace(r.name,'[[:space:]　]+','','g') in ('顔写真','証明写真','身分証明写真')
 and s.status in ('submitted','verified')
 and s.attachment_path ~ '[.](jpg|jpeg|png|heic|heif)$'
 order by case when r.scope in ('internal','both') then 0 else 1 end,r.sort_order,r.id
 limit 1);
end $$;
revoke all on function private.personnel_portrait_path(uuid,uuid) from public,anon;
grant execute on function private.personnel_portrait_path(uuid,uuid) to authenticated;

create function private.employee_personnel_view(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.personnel_view_allowed(p_company) then
 raise exception '社員情報の閲覧権限がありません' using errcode='42501'; end if;
 return jsonb_build_object('company_id',p_company,'records',coalesce((
 select jsonb_agg(jsonb_build_object(
 'id',w.id,'name',w.name,'kind',case when w.affiliation::text='partner_company' then 'partnerWorker' else 'employee' end,
 'role',coalesce(w.role,''),'phone',coalesce(w.phone,''),'employeeNumber',coalesce(w.employee_number,''),
 'department',coalesce(w.department,''),'hireDate',coalesce(w.hire_date::text,''),'active',w.status::text='active',
 'bloodType',coalesce(p.blood_type,''),'address',coalesce(p.address,''),
 'emergencyName',coalesce(p.emergency_name,''),'emergencyRelation',coalesce(p.emergency_relation,''),
 'emergencyPhone',coalesce(p.emergency_phone,''),'emergencyAddress',coalesce(p.emergency_address,''),
 'familyComposition',coalesce(p.family_composition,''),
 'familyMembers',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'relation',f.relation,
 'birth_date',f.birth_date,'is_dependent',f.is_dependent) order by f.birth_date nulls last,f.name)
 from public.worker_family_members f where f.company_id=w.company_id and f.worker_id=w.id),'[]'::jsonb),
 'createdAt',w.created_at,'updatedAt',greatest(w.updated_at,coalesce(p.updated_at,w.updated_at))
 ) order by w.name) from public.workers w
 left join public.worker_personnel_profiles p on p.company_id=w.company_id and p.worker_id=w.id
 where w.company_id=p_company and w.status::text='active'),'[]'::jsonb));
end $$;
revoke all on function private.employee_personnel_view(uuid) from public,anon;
grant execute on function private.employee_personnel_view(uuid) to authenticated;
create function public.employee_personnel_view(p_company uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.employee_personnel_view(p_company);
$$;
revoke all on function public.employee_personnel_view(uuid) from public,anon;
grant execute on function public.employee_personnel_view(uuid) to authenticated;
create function public.employee_personnel_portrait(p_company uuid,p_worker uuid)
returns text language sql stable security invoker set search_path='' as $$
 select private.personnel_portrait_path(p_company,p_worker);
$$;
revoke all on function public.employee_personnel_portrait(uuid,uuid) from public,anon;
grant execute on function public.employee_personnel_portrait(uuid,uuid) to authenticated;
-- Only the current saved portrait, not unrelated employee attachments. Existing
-- policies and no-overwrite/no-delete/account guards remain in force.
create policy employee_personnel_portrait_read on storage.objects for select to authenticated
using(bucket_id='worker-documents' and cardinality(string_to_array(name,'/'))=5
 and private.personnel_view_allowed(private.try_uuid(split_part(name,'/',1)))
 and name=private.personnel_portrait_path(private.try_uuid(split_part(name,'/',1)),private.try_uuid(split_part(name,'/',2))));
commit;
