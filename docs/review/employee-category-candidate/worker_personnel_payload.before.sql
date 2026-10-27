CREATE OR REPLACE FUNCTION private.worker_personnel_payload(p_worker_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'name',coalesce(w.name,''),
    'kind',case when w.affiliation::text='partner_company'
      then 'partnerWorker' else 'employee' end,
    'blood_type',coalesce(p.blood_type,''),
    'role',coalesce(w.role,''),
    'employee_number',coalesce(w.employee_number,''),
    'department',coalesce(w.department,''),
    'hire_date',coalesce(w.hire_date::text,''),
    'phone',coalesce(w.phone,''),
    'address',coalesce(p.address,''),
    'emergency_name',coalesce(p.emergency_name,''),
    'emergency_relation',coalesce(p.emergency_relation,''),
    'emergency_phone',coalesce(p.emergency_phone,''),
    'emergency_address',coalesce(p.emergency_address,''),
    'family_composition',coalesce(p.family_composition,''),
    'family_members',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',fm.id,'name',fm.name,'relation',fm.relation,
        'birth_date',fm.birth_date,'is_dependent',fm.is_dependent
      ) order by fm.birth_date nulls last,fm.name)
      from public.worker_family_members fm
      where fm.worker_id=w.id and fm.company_id=w.company_id
    ),'[]'::jsonb)
  )
  from public.workers w
  left join public.worker_personnel_profiles p on p.worker_id=w.id
  where w.id=p_worker_id
  limit 1
$function$

