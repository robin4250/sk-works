-- Keep the private implementation inaccessible to app roles.
revoke all on function private.change_personal_sko_id(text) from public, anon, authenticated;

-- The public RPC wrapper is the only callable surface.
create or replace function public.change_personal_sko_id(p_sko_id text)
returns text
language sql
security definer
set search_path = ''
as $$
  select private.change_personal_sko_id(p_sko_id)
$$;

alter function public.change_personal_sko_id(text) owner to postgres;
revoke all on function public.change_personal_sko_id(text) from public, anon;
grant execute on function public.change_personal_sko_id(text) to authenticated, service_role;
