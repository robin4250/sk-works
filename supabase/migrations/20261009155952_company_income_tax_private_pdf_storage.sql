-- Staged private PDF adoption only. No production application/upload/verification.
-- Operation-aware SELECT is required to permit downloads without object listing.
do $$
begin
 if to_regprocedure('storage.allow_any_operation(text[])') is null then
  raise exception 'operation-aware Storage helper is required';
 end if;
 if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='storage' and c.relname='objects' and c.relrowsecurity) then
  raise exception 'existing Storage objects RLS must be enabled';
 end if;
 if exists(select 1 from storage.buckets where id='company-income-tax-tables') then
  raise exception 'new private income tax bucket must not overwrite an existing bucket';
 end if;
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('company-income-tax-tables','company-income-tax-tables',false,10485760,array['application/pdf']);

create function income_tax_private.pdf_object_access(p_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare v_company uuid; v_version bigint;
begin
 if p_name is null or p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[1-9][0-9]{0,18}/[0-9a-f]{64}\.pdf$' then return false; end if;
 v_company := split_part(p_name,'/',1)::uuid;
 v_version := split_part(p_name,'/',3)::bigint;
 if v_version<=0 or auth.uid() is null or private.account_access_allowed() is distinct from true then return false; end if;
 return exists(select 1 from public.companies c join public.company_members cm on cm.company_id=c.id
  where c.id=v_company and cm.user_id=auth.uid() and cm.role::text in ('owner','admin'));
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end $$;
revoke all on function income_tax_private.pdf_object_access(text) from public,anon,authenticated;
grant execute on function income_tax_private.pdf_object_access(text) to authenticated;

-- Restrictive guards prevent unrelated broad permissive policies from granting
-- overwrite/delete/list/anonymous access to this new bucket. Other buckets pass.
create policy income_tax_pdf_insert_guard on storage.objects as restrictive for insert to authenticated
 with check(bucket_id<>'company-income-tax-tables' or
  (income_tax_private.pdf_object_access(name) and storage.allow_any_operation(array['object.upload'])));
create policy income_tax_pdf_insert on storage.objects for insert to authenticated
 with check(bucket_id='company-income-tax-tables' and income_tax_private.pdf_object_access(name)
  and storage.allow_any_operation(array['object.upload']));
create policy income_tax_pdf_read_guard on storage.objects as restrictive for select to authenticated
 using(bucket_id<>'company-income-tax-tables' or
  (income_tax_private.pdf_object_access(name) and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info','object.sign'])));
create policy income_tax_pdf_read on storage.objects for select to authenticated
 using(bucket_id='company-income-tax-tables' and income_tax_private.pdf_object_access(name)
  and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info','object.sign']));
create policy income_tax_pdf_no_update on storage.objects as restrictive for update to authenticated
 using(bucket_id<>'company-income-tax-tables') with check(bucket_id<>'company-income-tax-tables');
create policy income_tax_pdf_no_delete on storage.objects as restrictive for delete to authenticated
 using(bucket_id<>'company-income-tax-tables');
create policy income_tax_pdf_no_anon on storage.objects as restrictive for all to anon
 using(bucket_id<>'company-income-tax-tables') with check(bucket_id<>'company-income-tax-tables');

-- Metadata registration requires an uploaded object row in this exact bucket.
-- Storage row existence is not evidence that the reported SHA matches bytes.
create function income_tax_private.require_pdf_object()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform 1 from storage.objects o where o.bucket_id='company-income-tax-tables'
  and o.name=new.value->>'storage_path' for key share;
 if not found then raise exception 'private income tax PDF object is not uploaded' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function income_tax_private.require_pdf_object() from public,anon,authenticated;
create trigger income_tax_document_object_required before insert or update on income_tax_private.documents
 for each row execute function income_tax_private.require_pdf_object();
