-- Company-scoped employee identity. Existing personnel approval/RLS paths stay intact.
alter table public.workers
  add column if not exists employee_number text,
  add column if not exists department text,
  add column if not exists hire_date date;

create table if not exists private.worker_employee_number_counters (
  company_id uuid primary key,
  last_number bigint not null default 0 check(last_number >= 0)
);
alter table private.worker_employee_number_counters enable row level security;
revoke all on private.worker_employee_number_counters from public,anon,authenticated;

create or replace function private.assign_worker_employee_number()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_number bigint;
  v_candidate text;
begin
  -- Lock the same counter row for manual and automatic assignments.
  -- This also keeps simultaneous clients from allocating the same auto number.
  insert into private.worker_employee_number_counters(company_id,last_number)
  values(new.company_id,0)
  on conflict(company_id) do update set last_number=private.worker_employee_number_counters.last_number;
  new.employee_number:=nullif(btrim(new.employee_number),'');
  if new.employee_number is null then
    loop
      update private.worker_employee_number_counters
      set last_number=last_number+1 where company_id=new.company_id
      returning last_number into v_number;
      v_candidate:='S'||lpad(v_number::text,greatest(4,length(v_number::text)),'0');
      exit when not exists(select 1 from public.workers w
        where w.company_id=new.company_id
          and upper(btrim(w.employee_number))=v_candidate and w.id is distinct from new.id);
    end loop;
    new.employee_number:=v_candidate;
  end if;
  if length(new.employee_number)>40 then
    raise exception using errcode='22001',message='employee_number_too_long';
  end if;
  if exists(select 1 from public.workers w
    where w.company_id=new.company_id and w.id is distinct from new.id
      and upper(btrim(w.employee_number))=upper(new.employee_number)) then
    raise exception using errcode='23505',message='employee_number_duplicate',
      constraint='workers_company_employee_number_unique';
  end if;
  return new;
end $$;
revoke all on function private.assign_worker_employee_number() from public,anon,authenticated;

drop trigger if exists workers_assign_employee_number on public.workers;
create trigger workers_assign_employee_number
before insert or update of employee_number,company_id on public.workers
for each row execute function private.assign_worker_employee_number();

-- Never overwrite an existing nonblank manual number. Stable order gives old rows
-- deterministic defaults on first application; subsequent applications are no-ops.
do $$declare r record; begin
  for r in select id from public.workers
    where nullif(btrim(employee_number),'') is null order by company_id,created_at,id
  loop
    update public.workers set employee_number=null where id=r.id;
  end loop;
end $$;
create unique index if not exists workers_company_employee_number_unique
on public.workers(company_id,upper(btrim(employee_number)));

-- Added select columns inherit the existing workers RLS policy; contact grants stay unchanged.
grant select(employee_number,department,hire_date) on public.workers to authenticated;

create or replace function private.worker_personnel_payload(p_worker_id uuid)
returns jsonb
language sql
stable security definer
set search_path=''
as $$
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
$$;

create or replace function private.apply_worker_personnel_payload(
  p_worker_id uuid,p_payload jsonb,p_actor uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $$
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
$$;

create or replace function private.employee_personnel_rows()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
begin
  select cm.company_id into v_company
  from public.company_members cm
  where cm.user_id=v_user
    and cm.role::text in ('owner','admin','manager')
  limit 1;
  if v_company is null then
    raise exception '社員情報の閲覧権限がありません';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'worker_id',w.id,'name',w.name,
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
      ),'[]'::jsonb),
      'created_at',w.created_at,
      'updated_at',greatest(w.updated_at,coalesce(p.updated_at,w.updated_at))
    ) order by w.name)
    from public.workers w
    left join public.worker_personnel_profiles p
      on p.worker_id=w.id and p.company_id=w.company_id
    where w.company_id=v_company and w.status='active'
  ),'[]'::jsonb);
end
$$;

create or replace function public.save_worker_personnel_profile(
  p_worker_id uuid,p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_company uuid;
  v_existing boolean;
  v_request uuid;
  v_current jsonb;
  v_actor uuid:=auth.uid();
  v_actor_role text;
  v_required integer;
begin
  if v_actor is null then raise exception 'ログインが必要です'; end if;
  if not private.can_edit_worker_personnel(p_worker_id) then
    raise exception '社員個人情報を変更する権限がありません';
  end if;

  select w.company_id into v_company
  from public.workers w
  where w.id=p_worker_id;

  if v_company is null then raise exception '社員を確認できません'; end if;

  -- Reject a manual duplicate before a pending approval request is created.
  -- The trigger/index recheck at application time covers approval-time races.
  if p_payload ? 'employee_number' and nullif(btrim(p_payload->>'employee_number'),'') is not null then
    if length(btrim(p_payload->>'employee_number'))>40 then
      raise exception using errcode='22001',message='employee_number_too_long';
    end if;
    if exists(select 1 from public.workers w where w.company_id=v_company
      and w.id<>p_worker_id
      and upper(btrim(w.employee_number))=upper(btrim(p_payload->>'employee_number'))) then
      raise exception using errcode='23505',message='employee_number_duplicate',
        constraint='workers_company_employee_number_unique';
    end if;
  end if;


  select cm.role::text into v_actor_role
  from public.company_members cm
  where cm.company_id=v_company
    and cm.user_id=v_actor
  limit 1;

  if v_actor_role is null then
    raise exception '会社への所属が必要です';
  end if;

  select exists(
    select 1
    from public.worker_personnel_profiles p
    where p.worker_id=p_worker_id
  ) into v_existing;

  v_current:=private.worker_personnel_payload(p_worker_id);

  if not v_existing then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object(
      'status','saved',
      'requires_approval',false,
      'saved_directly',true
    );
  end if;

  if v_current=p_payload then
    return jsonb_build_object(
      'status','unchanged',
      'requires_approval',false,
      'saved_directly',false
    );
  end if;

  if v_actor_role in ('owner','admin') then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);

    update public.worker_personnel_change_requests
    set status='rejected',resolved_at=now()
    where worker_id=p_worker_id
      and status='pending';

    return jsonb_build_object(
      'status','saved',
      'requires_approval',false,
      'saved_directly',true
    );
  end if;

  select count(*)::integer into v_required
  from public.worker_personnel_approvers a
  where a.company_id=v_company
    and a.user_id<>v_actor;

  if v_required<1 then
    raise exception '社員個人情報の承認者を1〜3名で設定してください（申請者本人は承認できません）';
  end if;

  v_required:=least(v_required,3);

  update public.worker_personnel_change_requests
  set status='rejected',resolved_at=now()
  where worker_id=p_worker_id
    and requested_by=v_actor
    and status='pending';

  insert into public.worker_personnel_change_requests(
    company_id,worker_id,requested_by,proposed,required_approvals
  ) values(v_company,p_worker_id,v_actor,p_payload,v_required)
  returning id into v_request;

  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select v_company,a.user_id,'approval','社員個人情報の変更申請',
    '社員個人情報の変更申請があります。登録済み承認者の承認後に反映されます。',
    'worker_personnel_change',v_request
  from public.worker_personnel_approvers a
  where a.company_id=v_company
    and a.user_id<>v_actor;

  return jsonb_build_object(
    'status','pending',
    'requires_approval',true,
    'request_id',v_request,
    'required_approvals',v_required,
    'saved_directly',false
  );
end
$$;

-- Explicitly retain the existing authenticated-only public save surface.
revoke all on function public.save_worker_personnel_profile(uuid,jsonb) from public,anon;
grant execute on function public.save_worker_personnel_profile(uuid,jsonb) to authenticated;
