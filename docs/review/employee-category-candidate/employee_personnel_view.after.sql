CREATE OR REPLACE FUNCTION private.employee_personnel_view(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.personnel_view_allowed(p_company) then
 raise exception '社員情報の閲覧権限がありません' using errcode='42501'; end if;
 return jsonb_build_object('company_id',p_company,'records',coalesce((
 select jsonb_agg(jsonb_build_object(
 'employeeCategoryId',(select a.category_id from employee_category_private.assignments a where a.worker_id=w.id and a.company_id=w.company_id),
 'employeeCategoryName',(select c.name from employee_category_private.assignments a join employee_category_private.categories c on c.company_id=a.company_id and c.id=a.category_id where a.worker_id=w.id and a.company_id=w.company_id),
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
end $function$

