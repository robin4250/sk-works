-- Explicit monthly appendices only. Existing financial documents are not rewritten.
begin;
create table private.trade_document_attachments (
 subject_kind text not null check(subject_kind in ('payment_certificate','invoice')),
 subject_id uuid not null,company_id uuid not null references public.companies(id),
 source_revision text not null,month date not null check(extract(day from month)=1),
 version integer not null check(version>0),payload jsonb not null,
 created_by uuid not null,created_at timestamptz not null default now(),
 updated_by uuid not null,updated_at timestamptz not null default now(),
 primary key(subject_kind,subject_id)
);
alter table private.trade_document_attachments enable row level security;
revoke all on private.trade_document_attachments from public,anon,authenticated,service_role;

create table private.trade_document_templates (
 company_id uuid not null references public.companies(id),subject_kind text not null check(subject_kind in ('payment_certificate','invoice')),
 version integer not null,payload jsonb not null,primary key(company_id,subject_kind)
);
alter table private.trade_document_templates enable row level security;
revoke all on private.trade_document_templates from public,anon,authenticated,service_role;
create function private.trade_document_template(p_kind text,p_company uuid,p_expected_version integer default null,p_payload jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare role_name text; saved private.trade_document_templates; item text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'ログインが必要です。' using errcode='42501'; end if;
 select role::text into role_name from public.company_members where user_id=auth.uid() and company_id=p_company;
 if role_name is null or role_name not in ('owner','admin','manager','viewer') or p_kind not in ('payment_certificate','invoice') then
  raise exception '設定の閲覧権限がありません。' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('trade-template:'||p_kind||':'||p_company::text,0));
 select * into saved from private.trade_document_templates where company_id=p_company and subject_kind=p_kind;
 if p_payload is not null then
  if role_name not in ('owner','admin') then raise exception '管理者のみ変更できます。' using errcode='42501'; end if;
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
 return jsonb_build_object('version',coalesce(saved.version,0),'payload',coalesce(saved.payload,'{}'::jsonb),'can_manage',role_name in ('owner','admin'));
end $$;
revoke all on function private.trade_document_template(text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function private.trade_document_template(text,uuid,integer,jsonb) to authenticated;
create function public.trade_document_template(p_kind text,p_company uuid,p_expected_version integer default null,p_payload jsonb default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.trade_document_template(p_kind,p_company,p_expected_version,p_payload) $$;
revoke all on function public.trade_document_template(text,uuid,integer,jsonb) from public,anon,service_role;
grant execute on function public.trade_document_template(text,uuid,integer,jsonb) to authenticated;

create function private.trade_document_source(p_kind text,p_subject uuid,p_source_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid; counter_id uuid; start_day date; end_day date; rev text; st text;
 final_at timestamptz; total bigint; tax bigint; source_snapshot jsonb; counter jsonb;
 company public.companies; role_name text; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then
  raise exception 'ログインが必要です。' using errcode='42501'; end if;
 if p_kind='payment_certificate' then
  select company_id,partner_company_id,period_start,period_end,revision::text,status,finalized_at,gross_amount,snapshot
  into cid,counter_id,start_day,end_day,rev,st,final_at,total,source_snapshot
  from public.payment_certificates where id=p_subject for share;
 elsif p_kind='invoice' then
  select company_id,customer_id,billing_period_start,billing_period_end,updated_at::text,status,finalized_at,grand_total,invoices.tax,snapshot
  into cid,counter_id,start_day,end_day,rev,st,final_at,total,tax,source_snapshot
  from public.invoices where id=p_subject for share;
 else raise exception '書類の種類を確認してください。' using errcode='22023'; end if;
 select role::text into role_name from public.company_members where company_id=cid and user_id=auth.uid();
 if cid is null or role_name is null or role_name not in ('owner','admin','manager','viewer') then
  raise exception '書類の閲覧権限がありません。' using errcode='42501'; end if;
 if (p_kind='invoice' and rev::timestamptz is distinct from p_source_revision::timestamptz)
 or (p_kind='payment_certificate' and rev is distinct from p_source_revision) then
  raise exception '元の帳票が更新されています。開き直してください。' using errcode='40001'; end if;
 if start_day is null or end_day is null or date_trunc('month',start_day)<>date_trunc('month',end_day) then
  raise exception '同じ対象月の帳票が必要です。' using errcode='22023'; end if;
 select * into company from public.companies where id=cid for share;
 if p_kind='payment_certificate' then
  select jsonb_build_object('name',name,'address',coalesce(address,''),'corporate_number','',
    'representative_name',coalesce(president_name,'')) into counter
  from public.partner_companies where id=counter_id and company_id=cid;
  if jsonb_typeof(source_snapshot->'tax')='number' then tax:=(source_snapshot->>'tax')::bigint; end if;
 else
  select jsonb_build_object('name',coalesce(nullif(billing_name,''),name),'address',coalesce(billing_address,''),
    'corporate_number','','representative_name','') into counter
  from public.customers where id=counter_id and company_id=cid;
 end if;
 if counter is null then raise exception '相手先の会社を確認できません。' using errcode='22023'; end if;
 result:=jsonb_build_object('company_id',cid,'source_revision',rev,'month',to_char(start_day,'YYYY-MM'),
  'can_manage',role_name in ('owner','admin'),'source_locked',st<>'draft' or final_at is not null,
  'defaults',jsonb_build_object('version',1,'kind',case when p_kind='invoice' then 'acceptance' else 'order' end,
   'month',to_char(start_day,'YYYY-MM'),'period_start',date_trunc('month',start_day)::date,
   'period_end',(date_trunc('month',start_day)+interval '1 month - 1 day')::date,
   'total_amount_yen',total,'tax_amount_yen',tax,
   'issuer',jsonb_build_object('name',company.name,'address',coalesce(company.address,''),
     'corporate_number',coalesce(company.corporate_number,''),'representative_name',''),
   'counterparty',counter,'company_seal_snapshot',private.document_company_seal_snapshot(null,cid,true)->'company_seal_snapshot',
   'company_seal_enabled',company.company_seal_enabled));
 return result;
end $$;
revoke all on function private.trade_document_source(text,uuid,text) from public,anon,authenticated,service_role;

create function private.trade_document_attachment_workspace(p_kind text,p_subject uuid,p_source_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare source jsonb; saved private.trade_document_attachments;
begin
 source:=private.trade_document_source(p_kind,p_subject,p_source_revision);
 select * into saved from private.trade_document_attachments where subject_kind=p_kind and subject_id=p_subject;
 if saved.subject_id is not null and (saved.company_id<>(source->>'company_id')::uuid or
  saved.source_revision<>source->>'source_revision' or to_char(saved.month,'YYYY-MM')<>source->>'month') then
  raise exception '元帳票変更後の別添は再確認が必要です。' using errcode='40001'; end if;
 return source||jsonb_build_object('template',coalesce((select payload from private.trade_document_templates where company_id=(source->>'company_id')::uuid and subject_kind=p_kind),'{}'::jsonb),'attachment',case when saved.subject_id is null then null else
  jsonb_build_object('version',saved.version,'payload',saved.payload) end);
end $$;
revoke all on function private.trade_document_attachment_workspace(text,uuid,text) from public,anon,service_role;
grant execute on function private.trade_document_attachment_workspace(text,uuid,text) to authenticated;
create function public.trade_document_attachment_workspace(p_kind text,p_subject uuid,p_source_revision text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.trade_document_attachment_workspace(p_kind,p_subject,p_source_revision) $$;
revoke all on function public.trade_document_attachment_workspace(text,uuid,text) from public,anon,service_role;
grant execute on function public.trade_document_attachment_workspace(text,uuid,text) to authenticated;

create function private.save_trade_document_attachment(p_kind text,p_subject uuid,p_source_revision text,p_expected_version integer,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare source jsonb; saved private.trade_document_attachments; value jsonb; party text; field text; max_len int;
 total numeric; tax numeric; issued date; ordered date;
begin
 -- Serializes first saves too; row locks alone cannot lock a missing appendix.
 perform pg_advisory_xact_lock(hashtextextended('trade-appendix:'||p_kind||':'||p_subject::text,0));
 source:=private.trade_document_source(p_kind,p_subject,p_source_revision);
 if source->>'can_manage'<>'true' then raise exception '管理者のみ保存できます。' using errcode='42501'; end if;
 select * into saved from private.trade_document_attachments where subject_kind=p_kind and subject_id=p_subject for update;
 if p_expected_version is null or p_expected_version<>coalesce(saved.version,0) then
  raise exception '別添書類が更新されています。開き直してください。' using errcode='40001'; end if;
 if saved.subject_id is not null and (source->>'source_locked'='true' or saved.source_revision<>source->>'source_revision') then
  raise exception '確定済み又は元帳票変更後の別添は変更できません。' using errcode='55000'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>16384 then
  raise exception '入力内容が長すぎます。' using errcode='22023'; end if;
 if p_payload->>'version' is distinct from '1' or p_payload->>'kind' is distinct from source->'defaults'->>'kind'
 or p_payload->>'month' is distinct from source->>'month' then
  raise exception '書類の種類・対象月が一致しません。' using errcode='22023'; end if;
 foreach party in array array['issuer','counterparty'] loop
  foreach field in array array['name','address','corporate_number','representative_name'] loop
   max_len:=case field when 'name' then 120 when 'address' then 240 when 'corporate_number' then 13 else 80 end;
   if jsonb_typeof(p_payload->party->field) is distinct from 'string' or
    length(btrim(p_payload->party->>field))=0 or length(p_payload->party->>field)>max_len then
    raise exception '会社情報の未入力・文字数を確認してください。' using errcode='22023'; end if;
  end loop;
  if p_payload->party->>'corporate_number' !~ '^[0-9]{13}$' then
   raise exception '法人番号は13桁で入力してください。' using errcode='22023'; end if;
 end loop;
 -- Seal ownership and style are server-owned. The registered issuer cannot be renamed here.
 if p_payload->'issuer'->>'name' is distinct from source->'defaults'->'issuer'->>'name' then
  raise exception '自社名は会社登録内容を使用してください。' using errcode='22023'; end if;
 if p_payload->>'issue_date' !~ '^\d{4}-\d{2}-\d{2}$' or p_payload->>'issue_date' is null then
  raise exception '発行日を入力してください。' using errcode='22023'; end if;
 issued:=(p_payload->>'issue_date')::date;
 foreach field in array array['intro_text','acceptance_text'] loop
  if p_payload ? field and (jsonb_typeof(p_payload->field)<>'string' or length(p_payload->>field)>400) then
   raise exception '文面は400文字以内にしてください。' using errcode='22023'; end if;
 end loop;
 if p_kind='invoice' then
  if p_payload->>'order_date' !~ '^\d{4}-\d{2}-\d{2}$' or p_payload->>'order_date' is null then
   raise exception '受領注文書日を入力してください。' using errcode='22023'; end if;
  ordered:=(p_payload->>'order_date')::date;
  if ordered>issued then raise exception '承諾日は注文書日以降にしてください。' using errcode='22023'; end if;
 else
  foreach field in array array['work_name','work_address','period_start','period_end','payment_conditions'] loop
   if jsonb_typeof(p_payload->field) is distinct from 'string' or length(btrim(p_payload->>field))=0
    or length(p_payload->>field)>(case when field='payment_conditions' then 400 else 240 end) then
    raise exception '工事・工期・支払条件を確認してください。' using errcode='22023'; end if;
  end loop;
  if (p_payload->>'period_start')::date>(p_payload->>'period_end')::date then
   raise exception '工期の開始・終了を確認してください。' using errcode='22023'; end if;
  total:=(p_payload->>'total_amount_yen')::numeric; tax:=(p_payload->>'tax_amount_yen')::numeric;
  if total is null or tax is null or total<0 or tax<0 or tax>total or total<>trunc(total) or tax<>trunc(tax)
   or total>2147483647 or total is distinct from (source->'defaults'->>'total_amount_yen')::numeric then
   raise exception '当月の請負代金と消費税額を確認してください。' using errcode='22023'; end if;
 end if;
 if jsonb_typeof(p_payload->'notes') is distinct from 'string' or length(p_payload->>'notes')>600 then
  raise exception '特記事項は600文字以内にしてください。' using errcode='22023'; end if;
 value:=(p_payload-'company_seal_snapshot'-'company_seal_enabled')||jsonb_build_object(
  'company_seal_snapshot',source->'defaults'->'company_seal_snapshot',
  'company_seal_enabled',source->'defaults'->'company_seal_enabled');
 insert into private.trade_document_attachments(subject_kind,subject_id,company_id,source_revision,month,version,payload,created_by,updated_by)
 values(p_kind,p_subject,(source->>'company_id')::uuid,source->>'source_revision',((source->>'month')||'-01')::date,
  coalesce(saved.version,0)+1,value,auth.uid(),auth.uid())
 on conflict(subject_kind,subject_id) do update set payload=excluded.payload,version=excluded.version,updated_by=excluded.updated_by,updated_at=now()
 returning * into saved;
 return jsonb_build_object('version',saved.version,'payload',saved.payload);
end $$;
revoke all on function private.save_trade_document_attachment(text,uuid,text,integer,jsonb) from public,anon,service_role;
grant execute on function private.save_trade_document_attachment(text,uuid,text,integer,jsonb) to authenticated;
create function public.save_trade_document_attachment(p_kind text,p_subject uuid,p_source_revision text,p_expected_version integer,p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.save_trade_document_attachment(p_kind,p_subject,p_source_revision,p_expected_version,p_payload) $$;
revoke all on function public.save_trade_document_attachment(text,uuid,text,integer,jsonb) from public,anon,service_role;
grant execute on function public.save_trade_document_attachment(text,uuid,text,integer,jsonb) to authenticated;
commit;
