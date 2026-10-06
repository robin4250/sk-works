-- Preregistered employees are active employees immediately for attendance
-- sheets and individual payroll settings, even before first-login linkage.
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
    'active',
    null
  )
  returning id into v_worker_id;

  return v_worker_id;
end;
$$;

update public.workers
set status='active',
    updated_at=now()
where affiliation::text='employee'
  and status='inactive'
  and user_id is null
  and coalesce(trim(phone),'')<>'';

revoke all on function public.register_employee_preregistration(text,text)
from public, anon;
grant execute on function public.register_employee_preregistration(text,text)
to authenticated;
