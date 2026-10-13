drop policy if exists "managers can manage workers" on public.workers;
create policy "people managers can manage workers"
on public.workers
for all
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_people')
)
with check (
  private.has_company_feature(company_id, 'can_manage_people')
);

drop policy if exists "managers can manage partner companies" on public.partner_companies;
create policy "people managers can manage partner companies"
on public.partner_companies
for all
to authenticated
using (
  private.has_company_feature(company_id, 'can_manage_people')
)
with check (
  private.has_company_feature(company_id, 'can_manage_people')
);
