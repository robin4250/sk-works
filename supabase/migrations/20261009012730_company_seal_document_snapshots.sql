-- Future documents only. No UPDATE/backfill of existing financial records.
create function private.document_company_seal_snapshot(p_existing jsonb,p_company uuid,p_new boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.companies;
begin
 if not p_new then
  if coalesce(p_existing,'{}'::jsonb) ? 'company_seal_snapshot' then
   return jsonb_build_object('company_seal_snapshot',p_existing->'company_seal_snapshot');
  end if;
  return '{}'::jsonb;
 end if;
 select * into c from public.companies where id=p_company for share;
 if c.id is null then raise exception 'Company does not exist.' using errcode='23503'; end if;
 if c.name is null or btrim(c.name)='' then
  raise exception 'Registered company name is missing.' using errcode='22023';
 end if;
 if c.company_seal_style not in ('legacy','aoyagi_reisho') then
  raise exception 'Unknown company seal style.' using errcode='22023';
 end if;
 if c.company_seal_style='aoyagi_reisho' and not private.aoyagi_reisho_name_supported(c.name) then
  raise exception 'Registered company name cannot be used for the selected seal.' using errcode='22023';
 end if;
 return jsonb_build_object('company_seal_snapshot',jsonb_build_object(
  'version',1,'style',c.company_seal_style,'name',c.name));
end $$;
revoke all on function private.document_company_seal_snapshot(jsonb,uuid,boolean) from public,anon,authenticated;

create function private.preserve_document_company_seal_snapshot() returns trigger
language plpgsql security definer set search_path='' as $$
declare previous jsonb; incoming jsonb; preserved jsonb;
begin
 if tg_table_name='payroll_statements' then
  incoming:=coalesce(new.detail,'{}'::jsonb);
  if tg_op='UPDATE' then previous:=old.detail; end if;
 else
  incoming:=coalesce(new.snapshot,'{}'::jsonb);
  if tg_op='UPDATE' then previous:=old.snapshot; end if;
 end if;
 preserved:=private.document_company_seal_snapshot(previous,new.company_id,tg_op='INSERT');
 if tg_table_name='payroll_statements' then
  new.detail:=(incoming-'company_seal_snapshot')||preserved;
 else
  new.snapshot:=(incoming-'company_seal_snapshot')||preserved;
 end if;
 return new;
end $$;
revoke all on function private.preserve_document_company_seal_snapshot() from public,anon,authenticated;
create trigger zz_company_seal_snapshot before insert or update on public.invoices
for each row execute function private.preserve_document_company_seal_snapshot();
create trigger zz_company_seal_snapshot before insert or update on public.payment_certificates
for each row execute function private.preserve_document_company_seal_snapshot();
create trigger zz_company_seal_snapshot before insert or update on public.payroll_statements
for each row execute function private.preserve_document_company_seal_snapshot();

-- Keep the same persisted seal metadata in the candidate BEFORE comparisons.
-- Fail on an unexpected generator definition instead of silently omitting it.
do $$
declare sig text; definition text; anchor text; addition text;
begin
 foreach sig in array array[
  'private.refresh_automatic_invoice(uuid,uuid,date)',
  'private.refresh_automatic_payment_certificate(uuid,uuid,date)'
 ] loop
  definition:=pg_get_functiondef(to_regprocedure(sig));
  anchor:='if existing.id is null then';
  addition:='snapshot_value:=snapshot_value||private.document_company_seal_snapshot(existing.snapshot,cid,existing.id is null);'||chr(10)||'  ';
  if definition is null or (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
   raise exception 'Unexpected document generator definition: %',sig;
  end if;
  execute replace(definition,anchor,addition||anchor);
 end loop;
 definition:=pg_get_functiondef('private.payroll_document_metadata(uuid)'::regprocedure);
 anchor:='''company_seal_enabled'',c.company_seal_enabled,';
 addition:='''company_seal_snapshot'',ps.detail->''company_seal_snapshot'','||chr(10)||' ';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Unexpected payroll document metadata definition.';
 end if;
 execute replace(definition,anchor,addition||anchor);
 definition:=pg_get_functiondef('public.company_seal_style_settings(uuid)'::regprocedure);
 anchor:='''company_seal_style'',c.company_seal_style)';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Unexpected company style settings definition.';
 end if;
 execute replace(definition,anchor,'''company_seal_style'',c.company_seal_style,''document_snapshot_version'',1)');
 -- Add only inside the new immutable agreement snapshot creation branch.
 definition:=pg_get_functiondef('private.saved_site_payment_document(uuid,uuid)'::regprocedure);
 anchor:='''snapshot_version'',2,';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Unexpected saved agreement document definition.';
 end if;
 definition:=replace(definition,anchor,'''snapshot_version'',3,');
 anchor:='''parent_company_seal_enabled'',parent.company_seal_enabled)';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
  raise exception 'Unexpected saved agreement seal definition.';
 end if;
 execute replace(definition,anchor,anchor||'||private.document_company_seal_snapshot(null,parent.id,true)');
end $$;
