create or replace function private.company_delivery_saved_state()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  return coalesce((
    select jsonb_agg(
      jsonb_build_object('item_key',s.item_key,'saved_at',s.saved_at)
      order by s.saved_at desc
    )
    from private.company_delivery_saved_items s
    where s.company_id=c
  ),'[]'::jsonb);
end
$$;

create or replace function public.company_delivery_saved_state()
returns jsonb language sql set search_path=''
as $$ select private.company_delivery_saved_state() $$;

revoke all on function public.company_delivery_saved_state() from public,anon;
grant execute on function public.company_delivery_saved_state() to authenticated;
