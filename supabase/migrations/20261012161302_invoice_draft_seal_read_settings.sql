-- Preserve the existing invoice-view authorization, ACL and search path.
-- No company table grants, historical documents or totals are changed.
do $migration$
declare
  target regprocedure := 'public.invoice_document_settings()'::regprocedure;
  source text;
  definition text;
begin
  select prosrc, pg_get_functiondef(oid) into source, definition
  from pg_proc where oid = target;
  if md5(source) <> 'd22f3318cded6e6cc1bdf68ec16fbb74' then
    raise exception 'invoice_document_settings changed; review before deployment';
  end if;
  if position('    ''company_name'', c.name,' in definition) = 0 then
    raise exception 'invoice document company settings marker missing';
  end if;
  definition := replace(definition,
    '    ''company_name'', c.name,',
    '    ''company_id'', c.id,
    ''company_seal_style'', c.company_seal_style,
    ''company_name'', c.name,');
  execute definition;
end;
$migration$;
