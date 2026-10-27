CREATE OR REPLACE FUNCTION private.apply_worker_personnel_payload(p_worker_id uuid, p_payload jsonb, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_company uuid;
  v_family jsonb;
  v_member jsonb;
  v_birth date;
  v_name text;
  v_relation text;
begin
  select w.company_id into v_company
  from public.workers w where w.id=p_worker_id for update;
  if v_company is null then raise exception '社員を確認できません'; end if;

  update public.workers
  set name=coalesce(nullif(trim(p_payload->>'name'),''),name),
      role=nullif(trim(coalesce(p_payload->>'role','')),''),
      phone=nullif(trim(coalesce(p_payload->>'phone','')),''),
      employee_number=case when p_payload ? 'employee_number' then p_payload->>'employee_number' else employee_number end,
      department=case when p_payload ? 'department' then nullif(btrim(p_payload->>'department'),'') else department end,
      hire_date=case when p_payload ? 'hire_date' then nullif(p_payload->>'hire_date','')::date else hire_date end,
      updated_at=now()
  where id=p_worker_id;

  insert into public.worker_personnel_profiles(
    worker_id,company_id,blood_type,address,
    emergency_name,emergency_relation,emergency_phone,emergency_address,
    family_composition,created_by,updated_by,updated_at
  )
  values(
    p_worker_id,v_company,
    nullif(trim(coalesce(p_payload->>'blood_type','')),''),
    nullif(trim(coalesce(p_payload->>'address','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_name','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_relation','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_phone','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_address','')),''),
    nullif(trim(coalesce(p_payload->>'family_composition','')),''),
    p_actor,p_actor,now()
  )
  on conflict(worker_id) do update
  set blood_type=excluded.blood_type,address=excluded.address,
      emergency_name=excluded.emergency_name,
      emergency_relation=excluded.emergency_relation,
      emergency_phone=excluded.emergency_phone,
      emergency_address=excluded.emergency_address,
      family_composition=excluded.family_composition,
      updated_by=excluded.updated_by,updated_at=now();

  v_family:=coalesce(p_payload->'family_members','[]'::jsonb);
  if jsonb_typeof(v_family)<>'array' then
    raise exception '家族構成データを確認してください';
  end if;

  delete from public.worker_family_members
  where worker_id=p_worker_id and company_id=v_company;

  for v_member in select value from jsonb_array_elements(v_family)
  loop
    v_name:=trim(coalesce(v_member->>'name',''));
    v_relation:=trim(coalesce(v_member->>'relation',''));
    if v_name='' or v_relation='' then
      raise exception '家族の氏名と続柄を入力してください';
    end if;
    begin
      v_birth:=nullif(v_member->>'birth_date','')::date;
    exception when others then
      raise exception '家族の誕生日を確認してください';
    end;

    insert into public.worker_family_members(
      company_id,worker_id,name,relation,birth_date,is_dependent,
      created_by,updated_by
    )
    values(
      v_company,p_worker_id,v_name,v_relation,v_birth,
      coalesce((v_member->>'is_dependent')::boolean,false),
      p_actor,p_actor
    );
  end loop;
end
$function$

