drop policy if exists "company_members_member_access"
  on public.company_members;

create policy "company_members_self_read"
on public.company_members
for select
to authenticated
using (
  user_id = auth.uid()
);
