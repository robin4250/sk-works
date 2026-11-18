begin;
set local lock_timeout='3s';
set local statement_timeout='20s';
do $migration$
declare
  source text := pg_get_functiondef('private.payroll_workspace()'::regprocedure);
  original constant text := $original$payload:=payload||jsonb_build_object('company_name',$original$;
  revised constant text := $revised$payload:=payload||jsonb_build_object('company_id',cid,'company_name',$revised$;
begin
  if (length(source) - length(replace(source, original, ''))) <> length(original) then
    raise exception 'Payroll workspace company payload differs from expected';
  end if;
  execute replace(source, original, revised);
end
$migration$;
commit;
