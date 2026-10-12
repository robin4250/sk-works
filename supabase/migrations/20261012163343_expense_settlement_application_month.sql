-- New settlement commands use the original application month in Japan.
-- Do not rewrite existing choices, command receipts, financial documents or history.
do $migration$
declare definition text; needle text := ' if claim.revision is distinct from p_revision then';
begin
 if (select md5(prosrc) from pg_proc where oid=
     'private.expense_approve_with_settlement(uuid,uuid,integer,text,date)'::regprocedure)
     is distinct from '0de6cf017fb6a1b463c9a85f3d7456ab' then
  raise exception 'Expense settlement prerequisite changed; review before applying';
 end if;
 definition := pg_get_functiondef(
   'private.expense_approve_with_settlement(uuid,uuid,integer,text,date)'::regprocedure);
 if length(definition)-length(replace(definition,needle,'')) <> length(needle) then
  raise exception 'Expense settlement application-month patch point is ambiguous';
 end if;
 -- Replay returns the old immutable receipt before this new-command validation.
 definition := replace(definition,needle,$patch$
 if p_settlement_month is distinct from
    date_trunc('month',claim.submitted_at at time zone 'Asia/Tokyo')::date then
  raise exception '精算対象月は申請月です。申請月で承認してください。' using errcode='22023';
 end if;
$patch$ || needle);
 execute definition;
end $migration$;
