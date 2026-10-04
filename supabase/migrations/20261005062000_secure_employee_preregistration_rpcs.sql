-- Mirrors production migration secure_employee_preregistration_rpcs.
-- Keep workers table direct privileges closed; expose only scoped RPCs.

create or replace function public.initial_registration_employee_rows()
returns table(
  id uuid,
  name text,
  phone text,
  user_id uuid,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    w.id,
    w.name,
    w.phone,
    w.user_id,
    w.status
  from public.workers w
  join public.company_members cm
    on cm.company_id = w.company_id
   and cm.user_id = auth.uid()
  where cm.role::text in ('owner','admin')
    and w.affiliation = 'employee'
    and coalesce(trim(w.phone), '') <> ''
  order by w.name nulls last, w.created_at, w.id
$$;

create or replace function public.register_employee_preregistration(
  p_name text,
  p_phone text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company_id uuid;
  v_worker_id uuid;
  v_name text := trim(coalesce(p_name,''));
  v_phone text := trim(coalesce(p_phone,''));
begin
  select cm.company_id
    into v_company_id
  from public.company_members cm
  where cm.user_id = auth.uid()
    and cm.role::text in ('owner','admin','manager')
  limit 1;

  if v_company_id is null then
    raise exception 'management permission required';
  end if;

  if v_name = '' or v_phone = '' then
    raise exception 'name and phone are required';
  end if;

  if exists (
    select 1
    from public.workers w
    where w.company_id = v_company_id
      and w.affiliation = 'employee'
      and w.phone = v_phone
  ) then
    raise exception 'employee phone already registered';
  end if;

  insert into public.workers(
    company_id,
    affiliation,
    name,
    phone,
    status,
    user_id
  )
  values(
    v_company_id,
    'employee',
    v_name,
    v_phone,
    'inactive',
    null
  )
  returning id into v_worker_id;

  return v_worker_id;
end;
$$;

revoke all on function public.initial_registration_employee_rows()
from public, anon;
grant execute on function public.initial_registration_employee_rows()
to authenticated;

revoke all on function public.register_employee_preregistration(text,text)
from public, anon;
grant execute on function public.register_employee_preregistration(text,text)
to authenticated;
