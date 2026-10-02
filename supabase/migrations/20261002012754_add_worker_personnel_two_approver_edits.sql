create table if not exists public.worker_personnel_profiles (
  worker_id uuid primary key references public.workers(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  blood_type text,
  address text,
  emergency_name text,
  emergency_relation text,
  emergency_phone text,
  emergency_address text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.worker_personnel_profiles enable row level security;

drop policy if exists "personnel profile read" on public.worker_personnel_profiles;
create policy "personnel profile read"
on public.worker_personnel_profiles for select
using (
  exists(
    select 1
    from public.workers w
    where w.id=worker_personnel_profiles.worker_id
      and w.company_id=worker_personnel_profiles.company_id
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

grant select on public.worker_personnel_profiles to authenticated;

create table if not exists public.worker_personnel_change_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  requested_by uuid not null,
  proposed jsonb not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists worker_personnel_change_requests_pending_idx
on public.worker_personnel_change_requests(company_id,status,created_at desc);

alter table public.worker_personnel_change_requests enable row level security;

create table if not exists public.worker_personnel_change_approvals (
  request_id uuid not null references public.worker_personnel_change_requests(id) on delete cascade,
  approver_user_id uuid not null,
  decision text not null check (decision in ('approve','reject')),
  created_at timestamptz not null default now(),
  primary key(request_id,approver_user_id)
);

alter table public.worker_personnel_change_approvals enable row level security;

insert into public.worker_personnel_profiles(
  worker_id,company_id,blood_type,address,
  emergency_name,emergency_relation,emergency_phone,emergency_address,
  created_by,updated_by,created_at,updated_at
)
select distinct on (eri.worker_id)
  eri.worker_id,
  eri.company_id,
  eri.blood_type,
  eri.address,
  eri.emergency_name,
  eri.emergency_relation,
  eri.emergency_phone,
  eri.emergency_address,
  eri.auth_user_id,
  eri.approved_by,
  coalesce(eri.approved_at,eri.created_at,now()),
  coalesce(eri.approved_at,eri.created_at,now())
from public.employee_registration_invites eri
where eri.worker_id is not null
  and eri.status='approved'
order by eri.worker_id, eri.approved_at desc nulls last, eri.created_at desc
on conflict(worker_id) do nothing;

create or replace function private.worker_personnel_payload(
  p_worker_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select jsonb_build_object(
    'name',coalesce(w.name,''),
    'kind',case
      when w.affiliation::text='partner_company' then 'partnerWorker'
      else 'employee'
    end,
    'blood_type',coalesce(p.blood_type,''),
    'role',coalesce(w.role,''),
    'phone',coalesce(w.phone,''),
    'address',coalesce(p.address,''),
    'emergency_name',coalesce(p.emergency_name,''),
    'emergency_relation',coalesce(p.emergency_relation,''),
    'emergency_phone',coalesce(p.emergency_phone,''),
    'emergency_address',coalesce(p.emergency_address,'')
  )
  from public.workers w
  left join public.worker_personnel_profiles p on p.worker_id=w.id
  where w.id=p_worker_id
  limit 1
$$;

create or replace function private.can_edit_worker_personnel(
  p_worker_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.workers w
    where w.id=p_worker_id
      and (
        w.user_id=auth.uid()
        or exists(
          select 1
          from public.company_members cm
          where cm.company_id=w.company_id
            and cm.user_id=auth.uid()
            and cm.role::text in ('owner','admin','manager')
        )
      )
  )
$$;

create or replace function private.is_worker_personnel_approver(
  p_company_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.company_approval_assignees a
    where a.company_id=p_company_id and a.user_id=auth.uid()
  )
  or exists(
    select 1
    from public.company_members cm
    where cm.company_id=p_company_id
      and cm.user_id=auth.uid()
      and cm.role::text in ('owner','admin')
  )
$$;

create or replace function private.apply_worker_personnel_payload(
  p_worker_id uuid,
  p_payload jsonb,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_company uuid;
begin
  select w.company_id into v_company
  from public.workers w
  where w.id=p_worker_id
  for update;

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
    created_by,updated_by,updated_at
  )
  values(
    p_worker_id,v_company,
    nullif(trim(coalesce(p_payload->>'blood_type','')),''),
    nullif(trim(coalesce(p_payload->>'address','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_name','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_relation','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_phone','')),''),
    nullif(trim(coalesce(p_payload->>'emergency_address','')),''),
    p_actor,p_actor,now()
  )
  on conflict(worker_id) do update
  set blood_type=excluded.blood_type,
      address=excluded.address,
      emergency_name=excluded.emergency_name,
      emergency_relation=excluded.emergency_relation,
      emergency_phone=excluded.emergency_phone,
      emergency_address=excluded.emergency_address,
      updated_by=excluded.updated_by,
      updated_at=now();
end
$$;

create or replace function public.save_worker_personnel_profile(
  p_worker_id uuid,
  p_payload jsonb
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
begin
  if v_actor is null then raise exception 'ログインが必要です'; end if;
  if not private.can_edit_worker_personnel(p_worker_id) then
    raise exception '社員個人情報を変更する権限がありません';
  end if;

  select w.company_id into v_company
  from public.workers w
  where w.id=p_worker_id;
  if v_company is null then raise exception '社員を確認できません'; end if;

  select exists(
    select 1 from public.worker_personnel_profiles p
    where p.worker_id=p_worker_id
  ) into v_existing;

  v_current:=private.worker_personnel_payload(p_worker_id);

  if not v_existing then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object('status','saved','requires_approval',false);
  end if;

  if v_current = p_payload then
    return jsonb_build_object('status','unchanged','requires_approval',false);
  end if;

  if (
    select count(distinct u.user_id)
    from (
      select a.user_id
      from public.company_approval_assignees a
      where a.company_id=v_company
      union
      select cm.user_id
      from public.company_members cm
      where cm.company_id=v_company
        and cm.role::text in ('owner','admin')
    ) u
    where u.user_id<>v_actor
  ) < 2 then
    raise exception '社員個人情報の編集には承認者が2名必要です';
  end if;

  update public.worker_personnel_change_requests
  set status='rejected',resolved_at=now()
  where worker_id=p_worker_id
    and requested_by=v_actor
    and status='pending';

  insert into public.worker_personnel_change_requests(
    company_id,worker_id,requested_by,proposed
  )
  values(v_company,p_worker_id,v_actor,p_payload)
  returning id into v_request;

  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select distinct
    v_company,u.user_id,'approval',
    '社員個人情報の変更申請',
    '社員個人情報の変更申請があります。2名の承認後に反映されます。',
    'worker_personnel_change',
    v_request
  from (
    select a.user_id
    from public.company_approval_assignees a
    where a.company_id=v_company
    union
    select cm.user_id
    from public.company_members cm
    where cm.company_id=v_company
      and cm.role::text in ('owner','admin')
  ) u
  where u.user_id<>v_actor;

  return jsonb_build_object(
    'status','pending',
    'requires_approval',true,
    'request_id',v_request
  );
end
$$;

create or replace function public.pending_worker_personnel_changes()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',r.id,
      'worker_id',r.worker_id,
      'worker_name',w.name,
      'requested_by',r.requested_by,
      'proposed',r.proposed,
      'created_at',r.created_at,
      'approval_count',(
        select count(*) from public.worker_personnel_change_approvals a
        where a.request_id=r.id and a.decision='approve'
      )
    ) order by r.created_at)
    from public.worker_personnel_change_requests r
    join public.workers w on w.id=r.worker_id
    where r.status='pending'
      and private.is_worker_personnel_approver(r.company_id)
      and r.requested_by<>v_user
  ),'[]'::jsonb);
end
$$;

create or replace function public.decide_worker_personnel_change(
  p_request_id uuid,
  p_approve boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_req public.worker_personnel_change_requests%rowtype;
  v_count integer;
begin
  select * into v_req
  from public.worker_personnel_change_requests
  where id=p_request_id
  for update;

  if not found or v_req.status<>'pending' then
    raise exception '変更申請を確認できません';
  end if;
  if v_req.requested_by=v_user then
    raise exception '自分の申請は承認できません';
  end if;
  if not private.is_worker_personnel_approver(v_req.company_id) then
    raise exception '承認権限がありません';
  end if;

  insert into public.worker_personnel_change_approvals(
    request_id,approver_user_id,decision
  )
  values(
    p_request_id,v_user,case when p_approve then 'approve' else 'reject' end
  )
  on conflict(request_id,approver_user_id) do nothing;

  if not p_approve then
    update public.worker_personnel_change_requests
    set status='rejected',resolved_at=now()
    where id=p_request_id;
    return jsonb_build_object('status','rejected');
  end if;

  select count(*) into v_count
  from public.worker_personnel_change_approvals a
  where a.request_id=p_request_id and a.decision='approve';

  if v_count>=2 then
    perform private.apply_worker_personnel_payload(
      v_req.worker_id,v_req.proposed,v_user
    );
    update public.worker_personnel_change_requests
    set status='approved',resolved_at=now()
    where id=p_request_id;

    insert into public.app_notifications(
      company_id,recipient_user_id,kind,title,body,action_key,action_id
    )
    values(
      v_req.company_id,v_req.requested_by,'approval',
      '社員個人情報の変更が承認されました',
      '2名の承認が完了し、社員個人情報へ反映されました。',
      'worker_personnel_change_completed',
      p_request_id
    );

    return jsonb_build_object('status','approved','approval_count',v_count);
  end if;

  return jsonb_build_object('status','pending','approval_count',v_count);
end
$$;

revoke all on function public.save_worker_personnel_profile(uuid,jsonb)
from public,anon;
revoke all on function public.pending_worker_personnel_changes()
from public,anon;
revoke all on function public.decide_worker_personnel_change(uuid,boolean)
from public,anon;

grant execute on function public.save_worker_personnel_profile(uuid,jsonb)
to authenticated;
grant execute on function public.pending_worker_personnel_changes()
to authenticated;
grant execute on function public.decide_worker_personnel_change(uuid,boolean)
to authenticated;
