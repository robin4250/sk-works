do $$
declare
  r record;
begin
  for r in
    select format('%I.%I', schemaname, tablename) as fqtn
    from pg_tables
    where schemaname = 'public'
  loop
    execute 'revoke all privileges on table ' || r.fqtn || ' from anon';
  end loop;
end
$$;
