begin;

-- PostgREST runs STABLE functions in read-only transactions.
-- The reauthentication check locks the matching session while reading status.
alter function public.retirement_render_state(uuid, uuid) volatile;
alter function public.retirement_render_state_pilot(uuid, uuid) volatile;

alter function public.retirement_vault_list_mine() volatile;
alter function public.retirement_vault_item_mine(uuid, text) volatile;

commit;
