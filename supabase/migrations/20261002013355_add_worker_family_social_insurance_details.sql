alter table public.worker_personnel_profiles
  add column if not exists family_composition text;

create table if not exists public.worker_family_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  name text not null,
  relation text not null,
  birth_date date,
  is_dependent boolean not null default false,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists worker_family_members_worker_idx
  on public.worker_family_members(worker_id,birth_date,name);

alter table public.worker_family_members enable row level security;

drop policy if exists "worker family members read" on public.worker_family_members;
create policy "worker family members read"
on public.worker_family_members for select
using (
  exists(
    select 1
    from public.workers w
    where w.id=worker_family_members.worker_id
      and w.company_id=worker_family_members.company_id
      and (
        w.user_id=(select auth.uid())
        or exists(
          select 1
          from public.company_members cm
          where cm.company_id=w.company_id
            and cm.user_id=(select auth.uid())
            and cm.role::text in ('owner','admin','manager')
        )
      )
  )
);

revoke insert,update,delete on public.worker_family_members from authenticated;
grant select on public.worker_family_members to authenticated;

update public.worker_personnel_profiles p
set family_composition=src.family_composition
from (
  select distinct on (eri.worker_id)
    eri.worker_id,
    eri.family_composition
  from public.employee_registration_invites eri
  where eri.worker_id is not null
    and eri.status='approved'
    and nullif(trim(coalesce(eri.family_composition,'')),'') is not null
  order by eri.worker_id,eri.approved_at desc nulls last,eri.created_at desc
) src
where p.worker_id=src.worker_id
  and nullif(trim(coalesce(p.family_composition,'')),'') is null;

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
