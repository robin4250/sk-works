drop policy if exists "company members can read line bindings"
  on public.line_group_bindings;

create policy "owners and admins can read line bindings"
on public.line_group_bindings
for select
to authenticated
using (
  private.has_company_role(
    company_id,
    array['owner'::app_role, 'admin'::app_role]
  )
);
