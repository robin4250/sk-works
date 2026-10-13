-- Staged same-company income table/PDF viewer read only. No production application.
DO $$ BEGIN
 if not exists(select 1 from pg_proc where oid=to_regprocedure('income_tax_private.pdf_object_access(text)') and md5(prosrc)='4fcbd39846252b9443657e6f71fa577a' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'income viewer prerequisite differs: pdf_object_access(text)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('income_tax_private.read_documents(uuid,text,text)') and md5(prosrc)='1f6ee6312f8d773a5d8a4005973b95a6' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'income viewer prerequisite differs: read_documents(uuid,text,text)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('income_tax_private.register_document(uuid,uuid,bigint,jsonb,boolean)') and md5(prosrc)='2abac3fbaf771cc9b813ceffd6bb67cd' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'income viewer prerequisite differs: register_document(uuid,uuid,bigint,jsonb,boolean)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('income_tax_private.require_admin(uuid)') and md5(prosrc)='2dd6aff22749cbfc188ee98dfd77882c' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'income viewer prerequisite differs: require_admin(uuid)';end if;
 if not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass and polname='income_tax_pdf_read' and polcmd='r' and polroles=ARRAY['authenticated'::regrole::oid] and polpermissive=true and md5(pg_get_expr(polqual,polrelid))='bd40f4f6c5ca8d73914b3fe5f6b2d820') then raise exception 'income PDF reader policy prerequisite differs: income_tax_pdf_read';end if;
 if not exists(select 1 from pg_policy where polrelid='storage.objects'::regclass and polname='income_tax_pdf_read_guard' and polcmd='r' and polroles=ARRAY['authenticated'::regrole::oid] and polpermissive=false and md5(pg_get_expr(polqual,polrelid))='d869820fc2aa9d7ca875e311efbf4bb0') then raise exception 'income PDF reader policy prerequisite differs: income_tax_pdf_read_guard';end if;
END $$;
create function income_tax_private.require_reader(p_company_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true or not exists(select 1 from public.company_members cm where cm.company_id=p_company_id and cm.user_id=auth.uid() and cm.role::text in ('owner','admin','viewer')) then raise exception 'income tax reader access denied' using errcode='42501';end if;
 perform 1 from public.companies where id=p_company_id for key share;
 if not found then raise exception 'income tax reader access denied' using errcode='42501';end if;
 return exists(select 1 from public.company_members cm where cm.company_id=p_company_id and cm.user_id=auth.uid() and cm.role::text in ('owner','admin'));
end$$;
revoke all on function income_tax_private.require_reader(uuid) from public,anon,authenticated;
create or replace function income_tax_private.read_documents(p_company_id uuid,p_payroll_date text,p_kind text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare can_edit boolean; v_date date; v_tables jsonb; v_selected jsonb; v_history jsonb;
begin
 can_edit:=income_tax_private.require_reader(p_company_id);
 if p_payroll_date is null or p_payroll_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or p_kind is null or p_kind not in ('monthly','daily','bonus','computer_calculation') then
  raise exception 'explicit civil payroll date and table kind required' using errcode='22023';
 end if;
 v_date := p_payroll_date::date;
 select coalesce(jsonb_agg(income_tax_private.table_state(d) order by (d.value->>'calendar_year')::integer desc,d.table_id),'[]'::jsonb)
 into v_tables from income_tax_private.documents d where d.company_id=p_company_id;
 select income_tax_private.table_state(d) into v_selected from income_tax_private.documents d
 join income_tax_private.verifications v on v.company_id=d.company_id and v.table_id=d.table_id and v.metadata_version=d.version
  and v.document_hash=d.value->>'document_hash' and v.storage_path=d.value->>'storage_path'
 where d.company_id=p_company_id and d.value->>'kind'=p_kind and (d.value->>'calendar_year')::integer=extract(year from v_date)::integer
 and (d.value->>'starts_on')::date<=v_date and v_date<(d.value->>'ends_before')::date and v.calculation_rules_hash is not null;
 if can_edit then
 select coalesce(jsonb_agg(to_jsonb(h)-'company_id' order by h.event_id desc),'[]'::jsonb)
 into v_history from (select * from income_tax_private.history where company_id=p_company_id order by event_id desc limit 100) h;
 else
  v_history:='[]';
  select coalesce(jsonb_agg(row_value-'registered_by' order by ord),'[]') into v_tables from jsonb_array_elements(v_tables) with ordinality expanded(row_value,ord);
  v_selected:=v_selected-'registered_by';
 end if;
 return jsonb_build_object('tables',v_tables,'selected',v_selected,'history',v_history,'can_edit',can_edit);
end $$;

create function income_tax_private.pdf_object_read_access(p_name text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare v_company uuid; v_version bigint;
begin
 if p_name is null or p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[1-9][0-9]{0,18}/[0-9a-f]{64}\.pdf$' then return false; end if;
 v_company := split_part(p_name,'/',1)::uuid;
 v_version := split_part(p_name,'/',3)::bigint;
 if v_version<=0 or auth.uid() is null or private.account_access_allowed() is distinct from true then return false; end if;
 return exists(select 1 from public.companies c join public.company_members cm on cm.company_id=c.id
  where c.id=v_company and cm.user_id=auth.uid() and cm.role::text in ('owner','admin','viewer')
  and (cm.role::text in ('owner','admin') or
   exists(select 1 from income_tax_private.documents d where d.company_id=v_company and d.value->>'storage_path'=p_name) or
   exists(select 1 from income_tax_private.history h where h.company_id=v_company and h.event_type='registration' and (h.before_value->>'storage_path'=p_name or h.after_value->>'storage_path'=p_name))));
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end $$;
revoke all on function income_tax_private.pdf_object_read_access(text) from public,anon,authenticated;
grant execute on function income_tax_private.pdf_object_read_access(text) to authenticated;

-- Only SELECT expressions change; upload/admin helper and immutable write guards stay intact.
alter policy income_tax_pdf_read_guard on storage.objects using(bucket_id<>'company-income-tax-tables' or
 (income_tax_private.pdf_object_read_access(name) and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info','object.sign'])));
alter policy income_tax_pdf_read on storage.objects using(bucket_id='company-income-tax-tables' and income_tax_private.pdf_object_read_access(name)
 and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info','object.sign']));
