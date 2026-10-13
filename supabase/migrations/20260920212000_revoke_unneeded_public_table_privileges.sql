do $$
declare
  r record;
begin
  for r in
    select format('%I.%I', schemaname, tablename) as fqtn
    from pg_tables
    where schemaname = 'public'
  loop
    execute 'revoke truncate, references, trigger on table ' || r.fqtn || ' from anon, authenticated';
  end loop;
end
$$;
