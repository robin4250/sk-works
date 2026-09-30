-- Harden vehicle/route table grants after creation.
-- Supabase default ACLs can grant broad table privileges; SKO keeps anon out
-- and limits signed-in clients to the RLS-covered CRUD paths actually used.

revoke all on table public.vehicles from anon;
revoke all on table public.route_assignments from anon;

revoke delete, truncate, references, trigger
  on table public.vehicles from authenticated;
revoke delete, truncate, references, trigger
  on table public.route_assignments from authenticated;

grant select, insert, update on table public.vehicles to authenticated;
grant select, insert, update on table public.route_assignments to authenticated;
