-- Function-only fix; production application requires the reviewed deployment gates.
-- Function-only replacement: no payroll row writes or recalculation.
do $guard$
declare
  target oid := to_regprocedure('private.refresh_automatic_payroll_internal(uuid,uuid,date)');
  definition text;
  original_body text;
  old_line constant text := 'category:=a.work_category;';
  new_line constant text := 'category:=coalesce(a.work_category,''day'');';
begin
  if target is null or not exists (
    select 1 from pg_proc p join pg_language l on l.oid=p.prolang
    where p.oid=target and md5(p.prosrc)='2c5230eea880fe8cddbe60bc6c4c0782'
      and p.prosecdef and p.proconfig=array['search_path=""'] and l.lanname='plpgsql'
  ) then
    raise exception 'payroll null-category prerequisite differs';
  end if;
  select prosrc into original_body from pg_proc where oid=target;
  if (length(original_body)-length(replace(original_body,old_line,'')))/length(old_line)<>1 then
    raise exception 'payroll category replacement must occur exactly once';
  end if;
  definition:=pg_get_functiondef(target);
  execute replace(definition,old_line,new_line);
  if not exists (select 1 from pg_proc where oid=target
    and prosrc=replace(original_body,old_line,new_line)) then
    raise exception 'payroll null-category body verification failed';
  end if;
end $guard$;
