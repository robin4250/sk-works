create or replace function public.people_management_records()
returns table(
  id uuid,
  kind text,
  name text,
  company_name text,
  phone text,
  email text,
  role text,
  notes text,
  active boolean
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id, 'can_manage_people') then
    raise exception 'people management permission required';
  end if;

  return query
  select
    pc.id,
    'partnerCompany'::text,
    pc.name,
    ''::text,
    coalesce(pc.phone, ''),
    coalesce(pc.email, ''),
    coalesce(pc.trade_role, ''),
    coalesce(pc.notes, ''),
    coalesce(pc.status, 'active') = 'active'
  from public.partner_companies pc
  where pc.company_id = v_company_id

  union all

  select
    w.id,
    case when w.affiliation::text = 'employee'
      then 'employee'::text else 'partnerWorker'::text end,
    w.name,
    coalesce(pc.name, ''),
    coalesce(w.phone, ''),
    coalesce(w.email, ''),
    coalesce(w.role, ''),
    coalesce(w.notes, ''),
    coalesce(w.status, 'active') = 'active'
  from public.workers w
  left join public.partner_companies pc
    on pc.id = w.partner_company_id
   and pc.company_id = w.company_id
  where w.company_id = v_company_id
  order by 3;
end;
$$;

revoke execute on function public.people_management_records()
  from public, anon;
grant execute on function public.people_management_records()
  to authenticated;

revoke select on table public.workers
  from public, anon, authenticated;
grant select (
  id, company_id, affiliation, partner_company_id, name, kana,
  status, created_at, updated_at, role, user_id
) on table public.workers to authenticated;

revoke select on table public.partner_companies
  from public, anon, authenticated;
grant select (
  id, company_id, name, trade_role, status, created_at, updated_at
) on table public.partner_companies to authenticated;
