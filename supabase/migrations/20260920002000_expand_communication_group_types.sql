do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.communication_groups'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%group_type%'
  loop
    execute format(
      'alter table public.communication_groups drop constraint if exists %I',
      c.conname
    );
  end loop;
end $$;

alter table public.communication_groups
  add constraint communication_groups_group_type_check
  check (group_type in ('company','site','direct','partner'));
