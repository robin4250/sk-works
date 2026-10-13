revoke all on table public.company_members from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.company_members from authenticated;
grant select on table public.company_members to authenticated;
