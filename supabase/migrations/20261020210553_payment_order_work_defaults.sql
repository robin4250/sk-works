-- Extend only order template text fields; saved monthly attachments stay unchanged.
begin;
DO $guard$
BEGIN
 IF (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('private.trade_document_template(text,uuid,integer,jsonb)')) IS DISTINCT FROM $original$
declare role_name text; can_manage boolean; saved private.trade_document_templates; item text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'ログインが必要です。' using errcode='42501'; end if;
 select role::text into role_name from public.company_members where user_id=auth.uid() and company_id=p_company;
 if p_kind='invoice' then can_manage:=coalesce(private.has_company_feature(p_company,'can_manage_invoices'),false);
 else can_manage:=coalesce(role_name in ('owner','admin','manager'),false); end if;
 if role_name is null or not can_manage or p_kind not in ('payment_certificate','invoice') then
  raise exception '設定の閲覧権限がありません。' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('trade-template:'||p_kind||':'||p_company::text,0));
 select * into saved from private.trade_document_templates where company_id=p_company and subject_kind=p_kind;
 if p_payload is not null then
  if not can_manage then raise exception '管理者のみ変更できます。' using errcode='42501'; end if;
  if p_expected_version is null or p_expected_version<>coalesce(saved.version,0) then raise exception '設定を再読込してください。' using errcode='40001'; end if;
  if jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>8192 then raise exception '設定内容を確認してください。' using errcode='22023'; end if;
  for item in select jsonb_object_keys(p_payload) loop
   if item not in ('intro_text','acceptance_text','payment_conditions','notes') or jsonb_typeof(p_payload->item)<>'string'
    or length(p_payload->>item)>(case when item='notes' then 600 else 400 end) then
    raise exception '設定項目・文字数を確認してください。' using errcode='22023'; end if;
  end loop;
  insert into private.trade_document_templates values(p_company,p_kind,coalesce(saved.version,0)+1,p_payload)
   on conflict(company_id,subject_kind) do update set version=excluded.version,payload=excluded.payload returning * into saved;
 end if;
 return jsonb_build_object('version',coalesce(saved.version,0),'payload',coalesce(saved.payload,'{}'::jsonb),'can_manage',can_manage);
end $original$ THEN
  RAISE EXCEPTION 'trade document template definition changed';
 END IF;
END $guard$;
create or replace function private.trade_document_template(p_kind text,p_company uuid,p_expected_version integer default null,p_payload jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare role_name text; can_manage boolean; saved private.trade_document_templates; item text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'ログインが必要です。' using errcode='42501'; end if;
 select role::text into role_name from public.company_members where user_id=auth.uid() and company_id=p_company;
 if p_kind='invoice' then can_manage:=coalesce(private.has_company_feature(p_company,'can_manage_invoices'),false);
 else can_manage:=coalesce(role_name in ('owner','admin','manager'),false); end if;
 if role_name is null or not can_manage or p_kind not in ('payment_certificate','invoice') then
  raise exception '設定の閲覧権限がありません。' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('trade-template:'||p_kind||':'||p_company::text,0));
 select * into saved from private.trade_document_templates where company_id=p_company and subject_kind=p_kind;
 if p_payload is not null then
  if not can_manage then raise exception '管理者のみ変更できます。' using errcode='42501'; end if;
  if p_expected_version is null or p_expected_version<>coalesce(saved.version,0) then raise exception '設定を再読込してください。' using errcode='40001'; end if;
  if jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>8192 then raise exception '設定内容を確認してください。' using errcode='22023'; end if;
  for item in select jsonb_object_keys(p_payload) loop
   if (item not in ('intro_text','acceptance_text','payment_conditions','notes')
       and not (p_kind='payment_certificate' and item in ('work_name','work_address'))) or jsonb_typeof(p_payload->item)<>'string'
    or length(p_payload->>item)>(case when item='notes' then 600 when item in ('work_name','work_address') then 240 else 400 end) then
    raise exception '設定項目・文字数を確認してください。' using errcode='22023'; end if;
  end loop;
  insert into private.trade_document_templates values(p_company,p_kind,coalesce(saved.version,0)+1,p_payload)
   on conflict(company_id,subject_kind) do update set version=excluded.version,payload=excluded.payload returning * into saved;
 end if;
 return jsonb_build_object('version',coalesce(saved.version,0),'payload',coalesce(saved.payload,'{}'::jsonb),'can_manage',can_manage);
end $$;
commit;
