-- Supabase may grant public-schema functions to API roles through default
-- privileges. Restrict the LINE binding RPCs explicitly.

revoke execute on function public.begin_line_group_claim(uuid) from anon;
revoke execute on function public.begin_line_group_claim(uuid) from public;
grant execute on function public.begin_line_group_claim(uuid) to authenticated;

revoke execute on function public.complete_line_group_claim_for_line(text, text) from anon;
revoke execute on function public.complete_line_group_claim_for_line(text, text) from authenticated;
revoke execute on function public.complete_line_group_claim_for_line(text, text) from public;
grant execute on function public.complete_line_group_claim_for_line(text, text) to service_role;

revoke execute on function public.disable_line_group_binding(uuid) from anon;
revoke execute on function public.disable_line_group_binding(uuid) from public;
grant execute on function public.disable_line_group_binding(uuid) to authenticated;
