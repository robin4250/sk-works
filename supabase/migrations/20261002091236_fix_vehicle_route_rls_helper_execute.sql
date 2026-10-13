grant usage on schema private to authenticated, service_role, supabase_storage_admin;
grant execute on function private.can_manage_vehicle_routes(uuid,text)
  to authenticated, service_role, supabase_storage_admin;
