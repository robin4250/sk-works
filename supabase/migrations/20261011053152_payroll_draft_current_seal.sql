-- Read current saved seal for drafts; finalized metadata remains snapshot-backed.
-- No existing statement, snapshot, history or review row is rewritten.
begin;
do $$
declare definition text; anchor text; replacement text;
begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_live_document_metadata(uuid)') and md5(prosrc)='1ba003365a9154f6e66bcb04c884710e' and prosecdef and proconfig=array['search_path=""'])
 or not exists(select 1 from pg_proc where oid=to_regprocedure('private.payroll_document_metadata(uuid)') and md5(prosrc)='a9054071dad46e9ecbed8d87af503f4b' and prosecdef and proconfig=array['search_path=""'])
 or not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_final_private.finalize(uuid,integer,boolean)') and md5(prosrc)='a054275c4308f62d3f9483175986396b' and prosecdef and proconfig=array['search_path=""']) then
  raise exception 'payroll draft seal prerequisite differs';
 end if;
 select pg_get_functiondef('private.payroll_live_document_metadata(uuid)'::regprocedure) into definition;
 anchor:='''company_seal_snapshot'',ps.detail->''company_seal_snapshot'',';
 replacement:='''company_seal_snapshot'',case when ps.workflow_state=''draft'' then jsonb_build_object(''version'',1,''style'',c.company_seal_style,''name'',c.name,''company_id'',c.id) else ps.detail->''company_seal_snapshot'' end,';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'payroll draft seal anchor differs';
 end if;
 execute replace(definition,anchor,replacement);
end $$;
commit;
