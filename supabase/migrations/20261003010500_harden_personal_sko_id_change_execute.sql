revoke execute on function public.change_personal_sko_id(text) from anon;
revoke execute on function public.change_personal_sko_id(text) from public;
grant execute on function public.change_personal_sko_id(text) to authenticated;

revoke execute on function private.change_personal_sko_id(text) from anon;
revoke execute on function private.change_personal_sko_id(text) from public;
revoke execute on function private.change_personal_sko_id(text) from authenticated;
