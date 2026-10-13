create or replace function public.site_directory_rows()
returns table(
  id uuid,
  name text,
  address text,
  starts_at date,
  ends_at date,
  status text,
  notes text,
  customer_name text,
  manager_name text
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

  if v_company_id is null then
    raise exception 'company membership not found';
  end if;

  return query
  select
    s.id,
    s.name,
    coalesce(s.address, ''),
    s.starts_at,
    s.ends_at,
    s.status::text,
    coalesce(s.notes, ''),
    coalesce(c.name, ''),
    coalesce(w.name, '')
  from public.sites s
  left join public.customers c
    on c.id = s.customer_id
   and c.company_id = s.company_id
  left join public.workers w
    on w.id = s.manager_worker_id
   and w.company_id = s.company_id
  where s.company_id = v_company_id
  order by s.created_at desc;
end;
$$;

revoke execute on function public.site_directory_rows()
  from public, anon;
grant execute on function public.site_directory_rows()
  to authenticated;

drop policy if exists "company members can read customers"
  on public.customers;
drop policy if exists "managers can manage customers"
  on public.customers;

create policy "invoice viewers can read customers"
on public.customers
for select
to authenticated
using (
  private.has_company_feature(company_id, 'can_view_invoices')
);

create policy "invoice managers can manage customers"
on public.customers
for all
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_invoices')
)
with check (
  private.has_company_feature(company_id, 'can_manage_invoices')
);
