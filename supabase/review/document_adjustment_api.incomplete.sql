-- REVIEW ONLY: requires full source integration, approval tests and UI adapter.
begin;
create table document_adjustment_private.previews (
 token uuid primary key default gen_random_uuid(),
 actor_id uuid not null, request jsonb not null,
 source_snapshot jsonb not null, source_total bigint not null,
 result_total bigint not null, result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table document_adjustment_private.previews enable row level security;
revoke all on document_adjustment_private.previews from public,anon,authenticated;

create function document_adjustment_private.authorize(p_company uuid,p_kind text,p_party uuid)
returns uuid language plpgsql security definer set search_path='' as $body$
declare actor uuid:=auth.uid();r text;
begin
 perform private.require_reauthentication_session();
 select role::text into r from public.company_members where company_id=p_company and user_id=actor;
 if r is null then raise sqlstate '42501' using message='会社へのアクセス権限がありません';end if;
 if p_kind='invoice' then
  if not private.has_company_feature(p_company,'can_manage_invoices') then
   raise sqlstate '42501' using message='請求書の編集権限がありません';end if;
  if p_party is not null and not exists(select 1 from public.customers where id=p_party and company_id=p_company) then
   raise sqlstate '42501' using message='取引会社を確認できません';end if;
 elsif p_kind='payment_certificate' then
  if r not in ('owner','admin') then raise sqlstate '42501' using message='支払証明書の編集権限がありません';end if;
  if p_party is not null and not exists(select 1 from public.partner_companies where id=p_party and company_id=p_company) then
   raise sqlstate '42501' using message='協力会社を確認できません';end if;
 else raise exception '帳票区分を確認できません';end if;
 return actor;
end $body$;
revoke all on function document_adjustment_private.authorize(uuid,text,uuid) from public,anon,authenticated;

create function document_adjustment_private.source(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare d jsonb;snap jsonb;
begin
 if p_month<>date_trunc('month',p_month)::date then raise exception '対象月を確認できません';end if;
 perform pg_advisory_xact_lock(hashtextextended(
  case p_kind when 'invoice' then 'invoice:' else 'payment-certificate:' end
   ||p_company::text||p_party::text||p_month::text,0));
 if p_kind='invoice' then
  if (select count(*) from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month)>1 then
   raise exception '同じ月に複数の請求書があるため対象を確認してください';end if;
  perform 1 from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month for update;
  if exists(select 1 from public.invoices i where i.company_id=p_company and i.customer_id=p_party and i.billing_period_start=p_month
   and (i.status<>'draft' or i.finalized_at is not null or i.approval_finalized_at is not null or coalesce(i.invoice_seal_frozen,false)
    or not i.automatic_calculation or exists(select 1 from public.invoice_approvals a where a.invoice_id=i.id and a.status='approved'))) then
   raise exception '確定・承認済みの請求書は変更できません';end if;
  perform private.refresh_automatic_invoice(p_company,p_party,p_month);
  select jsonb_build_object('id',id,'snapshot',snapshot,'total',grand_total,'updated_at',updated_at)
   into d from public.invoices where company_id=p_company and customer_id=p_party and billing_period_start=p_month;
 else
  perform 1 from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month for update;
  if exists(select 1 from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month
   and (status<>'draft' or finalized_at is not null or not automatic_calculation)) then
   raise exception '確定済みの支払証明書は変更できません';end if;
  perform private.refresh_automatic_payment_certificate(p_company,p_party,p_month);
  select jsonb_build_object('id',id,'snapshot',snapshot,'total',net_amount,'updated_at',updated_at)
   into d from public.payment_certificates where company_id=p_company and partner_company_id=p_party and period_start=p_month;
 end if;
 if d is null then
  if p_kind='invoice' then
   select jsonb_build_object('tax_rate_bps',coalesce(c.tax_rate,0)*100,
    'sites',coalesce((select jsonb_agg(jsonb_build_object('site_id',s.id,'site_name',s.name,
      'subtotal',0,'tax',0,'welfare_rate_bps',case when fs.welfare_rate between 0 and 100 then fs.welfare_rate*100 else 0 end,'lines','[]'::jsonb) order by s.created_at,s.id)
     from public.sites s left join public.site_financial_settings fs on fs.company_id=p_company and fs.site_id=s.id
     where s.company_id=p_company and s.customer_id=p_party),'[]'::jsonb)) into snap from public.companies c where c.id=p_company;
  else
   select jsonb_build_object('welfare_rate',coalesce(s.welfare_rate,0),'tax_rate',coalesce(s.tax_rate,10),'calculation_rows','[]'::jsonb)
    into snap from public.partner_payment_settings s where s.company_id=p_company and s.partner_company_id=p_party;
   if snap is null then snap:=jsonb_build_object('welfare_rate',0,'tax_rate',10,'calculation_rows','[]'::jsonb);end if;
  end if;
  d:=jsonb_build_object('id',null,'snapshot',snap,'total',0,'updated_at',null);
 end if;
 return d;
end $body$;
revoke all on function document_adjustment_private.source(uuid,text,uuid,date) from public,anon,authenticated;

create function public.read_trade_document_adjustments(p_company_id uuid,p_kind text,p_month date,p_party_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare parties jsonb;entries jsonb:='[]';sites jsonb:='[]';items jsonb;src jsonb;
 ready boolean;locked boolean:=false;v bigint:=0;
begin
 perform document_adjustment_private.authorize(p_company_id,p_kind,p_party_id);
 if p_month is null or p_month<>date_trunc('month',p_month)::date then raise exception '対象月を確認できません';end if;
 select coalesce(enabled,false) into ready from document_adjustment_private.rollout where company_id=p_company_id;
 ready:=coalesce(ready,false);
 if p_kind='invoice' then
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'company_id',company_id,'kind',p_kind,'name',name) order by name,id),'[]') into parties
   from public.customers where company_id=p_company_id;
  if p_party_id is not null then
   select coalesce(bool_or(status<>'draft' or finalized_at is not null or approval_finalized_at is not null or coalesce(invoice_seal_frozen,false) or not automatic_calculation),false)
    into locked from public.invoices where company_id=p_company_id and customer_id=p_party_id and billing_period_start=p_month;
   locked:=locked or exists(select 1 from public.invoice_approvals a join public.invoices i on i.id=a.invoice_id
    where i.company_id=p_company_id and i.customer_id=p_party_id and i.billing_period_start=p_month and a.status='approved');
  end if;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'company_id',company_id,'kind',p_kind,'name',name) order by name,id),'[]') into parties
   from public.partner_companies where company_id=p_company_id;
  if p_party_id is not null then
   select coalesce(bool_or(status<>'draft' or finalized_at is not null or not automatic_calculation),false) into locked
    from public.payment_certificates where company_id=p_company_id and partner_company_id=p_party_id and period_start=p_month;
  end if;
 end if;
 if p_party_id is not null and ready and not locked then
  perform pg_advisory_xact_lock(hashtextextended(case p_kind when 'invoice' then 'invoice:' else 'payment-certificate:' end||p_company_id::text||p_party_id::text||p_month::text,0));
  -- Materialize one occurrence per template/month before source refresh. A
  -- retry cannot create a second occurrence or modify any finalized snapshot.
  items:=document_adjustment_private.active_items(p_company_id,p_kind,p_party_id,p_month);
  insert into document_adjustment_private.occurrences(template_id,month,template_version)
   select (x->>'template_id')::uuid,p_month,(x->>'template_version')::bigint from jsonb_array_elements(items) x
   on conflict(template_id,month) do nothing;
  src:=document_adjustment_private.source(p_company_id,p_kind,p_party_id,p_month);
  update document_adjustment_private.occurrences o set document_id=(src->>'id')::uuid
   from document_adjustment_private.templates t where t.id=o.template_id and t.company_id=p_company_id and t.kind=p_kind
    and t.party_id=p_party_id and o.month=p_month and o.document_id is null;
  items:=document_adjustment_private.active_items(p_company_id,p_kind,p_party_id,p_month);
  select coalesce(jsonb_agg(x||jsonb_build_object('id',x->'entry_id','editable',true,
   'can_stop',x->>'recurrence'='monthly','canceled',false,'template_stopped',false,'version',1)),'[]') into entries
   from jsonb_array_elements(items) x;
  if p_kind='invoice' then
   select coalesce(jsonb_agg(jsonb_build_object('id',x->'site_id','label',x->>'site_name')),'[]') into sites
    from jsonb_array_elements(src->'snapshot'->'sites') x where x->>'site_id' is not null;
  end if;
  select coalesce((select version from document_adjustment_private.scope_versions where company_id=p_company_id and kind=p_kind and party_id=p_party_id and month=p_month),0) into v;
 end if;
 return jsonb_build_object('company_id',p_company_id,'kind',p_kind,'month',p_month,'party_id',p_party_id,
  'parties',parties,'entries',entries,'version',v,'ready',ready,'can_edit',not locked,'locked',locked,
  'tax_mode','per_item','supported_modes',jsonb_build_array('before_charges','settlement_yen'),'charge_sites',sites);
end $body$;
revoke all on function public.read_trade_document_adjustments(uuid,text,date,uuid) from public,anon;
grant execute on function public.read_trade_document_adjustments(uuid,text,date,uuid) to authenticated;

create function document_adjustment_private.plan(p_request jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare cid uuid:=(p_request->>'company_id')::uuid;k text:=p_request->>'kind';
 party uuid:=(p_request->>'party_id')::uuid;m date:=(p_request->>'month')::date;
 a text:=p_request->>'action';scope text:=p_request->>'update_scope';
 items jsonb;next_items jsonb;entry jsonb;oid uuid;tid uuid;ver bigint;sv bigint;
begin
 if jsonb_typeof(p_request)<>'object' or not p_request ?& array['command_id','company_id','kind','party_id','month','expected_version','action','entry_id','sign','title','amount_yen','recurrence','effective_month','calculation_mode','site_id','expected_template_version','update_scope']
  or p_request->>'command_id' is null or p_request->>'company_id' is null or p_request->>'kind' is null
  or p_request->>'party_id' is null or p_request->>'month' is null or p_request->>'expected_version' is null
  or p_request->>'action' is null or p_request->>'effective_month' is null or p_request->>'calculation_mode' is null
  or p_request->>'update_scope' is null then raise exception '変更内容を確認できません';end if;
 perform document_adjustment_private.authorize(cid,k,party);
 if not exists(select 1 from document_adjustment_private.rollout where company_id=cid and enabled) then
  raise exception '項目の加減算は準備中です';end if;
 if a not in ('add','edit','cancel','stop') or scope not in ('current_month','from_month')
  or (p_request->>'effective_month')::date<>m or m<>date_trunc('month',m)::date
  or p_request->>'calculation_mode' not in ('before_charges','settlement_yen') then
  raise exception '変更内容と対象月を確認できません';end if;
 select coalesce((select version from document_adjustment_private.scope_versions where company_id=cid and kind=k and party_id=party and month=m),0) into sv;
 if sv is distinct from (p_request->>'expected_version')::bigint then raise exception '他の変更がありました。最新の内容を確認してください';end if;
 items:=document_adjustment_private.active_items(cid,k,party,m);
 if a='add' then
  if scope<>'current_month' then raise exception '追加の対象月を確認してください';end if;
  oid:=gen_random_uuid();tid:=gen_random_uuid();ver:=1;
 else
  oid:=(p_request->>'entry_id')::uuid;
  select x into entry from jsonb_array_elements(items) x where x->>'entry_id'=oid::text;
  if entry is null then raise exception '変更対象を確認できません';end if;
  tid:=(entry->>'template_id')::uuid;ver:=(entry->>'template_version')::bigint;
  if scope='from_month' and ver is distinct from (p_request->>'expected_template_version')::bigint then
   raise exception '毎月設定が変更されています';end if;
  if scope='from_month' and entry->>'recurrence'<>'monthly' then raise exception '毎月の項目ではありません';end if;
 end if;
 if a in ('add','edit') then
  if p_request->>'title' is null or p_request->>'amount_yen' is null or p_request->>'sign' is null or p_request->>'recurrence' is null
   or p_request->>'sign' not in ('plus','minus') or p_request->>'recurrence' not in ('once','monthly')
   or length(btrim(p_request->>'title')) not between 1 and 120
   or (p_request->>'amount_yen')::numeric<>trunc((p_request->>'amount_yen')::numeric)
   or (p_request->>'amount_yen')::numeric not between 1 and 2147483647 then
   raise exception '項目名・金額を確認してください';end if;
  if a='edit' and p_request->>'recurrence'<>entry->>'recurrence' then
   raise exception '繰り返し区分は新しい項目で登録してください';end if;
  if k='invoice' and p_request->>'calculation_mode'='before_charges' and not exists(
   select 1 from public.sites where id=(p_request->>'site_id')::uuid and company_id=cid and customer_id=party
  ) then raise exception '対象現場を確認してください';end if;
  if k='payment_certificate' and p_request->>'calculation_mode'='before_charges' and not exists(
   select 1 from public.partner_payment_settings where company_id=cid and partner_company_id=party
    and welfare_rate is not null and tax_rate is not null
  ) then raise exception '協力会社の福利厚生費・税率設定を確認してください';end if;
 end if;
 if (a='cancel' and scope<>'current_month') or (a='stop' and scope<>'from_month') then
  raise exception '削除・停止する範囲を確認してください';end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into next_items from jsonb_array_elements(items) x where x->>'entry_id' is distinct from oid::text;
 if a in ('add','edit') then
  entry:=jsonb_build_object('entry_id',oid,'template_id',tid,'template_version',ver,
   'title',btrim(p_request->>'title'),'sign',p_request->>'sign','amount_yen',(p_request->>'amount_yen')::bigint,
   'recurrence',p_request->>'recurrence','calculation_mode',p_request->>'calculation_mode',
   'site_id',p_request->>'site_id','month',m);
  next_items:=next_items||jsonb_build_array(entry);
 end if;
 return jsonb_build_object('old_items',items,'new_items',next_items,'entry',entry,'entry_id',oid,'template_id',tid,'template_version',ver,'version',sv);
end $body$;
revoke all on function document_adjustment_private.plan(jsonb) from public,anon,authenticated;

create function public.preview_trade_document_adjustment(p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare actor uuid;plan jsonb;src jsonb;d jsonb;token uuid;result jsonb;
begin
 actor:=document_adjustment_private.authorize((p_command->>'company_id')::uuid,p_command->>'kind',(p_command->>'party_id')::uuid);
 src:=document_adjustment_private.source((p_command->>'company_id')::uuid,p_command->>'kind',(p_command->>'party_id')::uuid,(p_command->>'month')::date);
 plan:=document_adjustment_private.plan(p_command);
 d:=document_adjustment_private.preview_delta(p_command->>'kind',src->'snapshot',plan->'old_items',plan->'new_items');
 if (src->>'total')::bigint+(d->>'total_delta_yen')::bigint not between -2147483648 and 2147483647 then
  raise exception '帳票の合計金額が保存可能な範囲を超えています';end if;
 token:=gen_random_uuid();
 result:=jsonb_build_object('request',p_command,'token',token,'base_total_yen',(src->>'total')::bigint,
  'result_total_yen',(src->>'total')::bigint+(d->>'total_delta_yen')::bigint,
  'welfare_yen',d->'welfare_delta_yen','tax_yen',d->'tax_delta_yen','adjustment_yen',d->'settlement_delta_yen');
 insert into document_adjustment_private.previews(token,actor_id,request,source_snapshot,source_total,result_total,result)
 values(token,actor,p_command,src,(src->>'total')::bigint,(result->>'result_total_yen')::bigint,result||jsonb_build_object('plan',plan));
 return result;
end $body$;
revoke all on function public.preview_trade_document_adjustment(jsonb) from public,anon;
grant execute on function public.preview_trade_document_adjustment(jsonb) to authenticated;

create function public.apply_trade_document_adjustment(p_command jsonb,p_preview_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare actor uuid;cid uuid:=(p_command->>'company_id')::uuid;k text:=p_command->>'kind';
 party uuid:=(p_command->>'party_id')::uuid;m date:=(p_command->>'month')::date;
 prev document_adjustment_private.previews%rowtype;c document_adjustment_private.commands%rowtype;
 src jsonb;after_source jsonb;plan jsonb;entry jsonb;tid uuid;oid uuid;v bigint;
 receipt jsonb;entry_data jsonb;current_version bigint;future record;
 future_states jsonb:='[]'::jsonb;future_after jsonb;
begin
 actor:=document_adjustment_private.authorize(cid,k,party);
 -- Serialize retries before checking the durable receipt.
 perform pg_advisory_xact_lock(hashtextextended('document-adjustment-command:'||(p_command->>'command_id'),0));
 select * into c from document_adjustment_private.commands where command_id=(p_command->>'command_id')::uuid;
 if found then
  if c.actor_id<>actor or c.company_id<>cid or c.request is distinct from p_command then
   raise exception '同じ保存番号で異なる操作はできません';end if;
  return c.receipt;
 end if;
 select * into prev from document_adjustment_private.previews where token=p_preview_token and actor_id=actor for update;
 if not found or prev.request is distinct from p_command or prev.created_at<clock_timestamp()-interval '10 minutes' then
  raise exception '計算結果をもう一度確認してください';end if;
 plan:=prev.result->'plan';tid:=(plan->>'template_id')::uuid;oid:=(plan->>'entry_id')::uuid;
 if p_command->>'update_scope'='from_month' then
  perform 1 from document_adjustment_private.templates where id=tid for update;
  select max(version) into current_version from document_adjustment_private.template_versions where template_id=tid;
  if current_version is distinct from (p_command->>'expected_template_version')::bigint then
   raise exception '毎月設定が変更されています';end if;
 end if;
 src:=document_adjustment_private.source(cid,k,party,m);
 if src is distinct from prev.source_snapshot then raise exception '帳票が変更されています。計算結果を確認してください';end if;
 -- Revalidate current permissions, scope CAS and item bindings under source lock.
 perform document_adjustment_private.plan(p_command);
 entry:=plan->'entry';v:=(plan->>'template_version')::bigint;
 entry_data:=jsonb_build_object('title',entry->>'title','sign',entry->>'sign','amount_yen',entry->'amount_yen',
  'calculation_mode',entry->>'calculation_mode','site_id',entry->>'site_id');
 if p_command->>'action'='add' then
  insert into document_adjustment_private.templates(id,company_id,kind,party_id,recurrence,created_by)
   values(tid,cid,k,party,p_command->>'recurrence',actor);
  insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,site_id,actor_id)
   values(tid,1,m,entry->>'title',entry->>'sign',(entry->>'amount_yen')::bigint,entry->>'calculation_mode',(entry->>'site_id')::uuid,actor);
  insert into document_adjustment_private.occurrences(id,template_id,month,document_id,template_version)
   values(oid,tid,m,(src->>'id')::uuid,1);
 elsif p_command->>'action'='cancel' then
  update document_adjustment_private.occurrences set canceled=true where id=oid and template_id=tid and month=m;
 elsif p_command->>'update_scope'='from_month' then
  insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,site_id,actor_id,stopped)
   values(tid,v+1,m,entry->>'title',entry->>'sign',(entry->>'amount_yen')::bigint,entry->>'calculation_mode',(entry->>'site_id')::uuid,actor,p_command->>'action'='stop');
  update document_adjustment_private.occurrences set template_version=v+1,override=null where id=oid;
 else
  update document_adjustment_private.occurrences set override=entry_data where id=oid and template_id=tid and month=m;
 end if;
 insert into document_adjustment_private.scope_versions(company_id,kind,party_id,month,version)
  values(cid,k,party,m,1) on conflict(company_id,kind,party_id,month) do update set version=document_adjustment_private.scope_versions.version+1
  returning version into current_version;
 after_source:=document_adjustment_private.source(cid,k,party,m);
 if (after_source->>'total')::bigint is distinct from prev.result_total then
  raise exception '登録後の合計と確認した計算結果が一致しません。保存を取り消しました';end if;
 if p_command->>'update_scope'='from_month' or (p_command->>'action'='add' and p_command->>'recurrence'='monthly') then
  -- Refresh already-created future drafts in chronological lock order. Frozen
  -- documents retain their saved snapshot and never enter this projection.
  for future in
   select billing_period_start as month,jsonb_build_object('id',id,'snapshot',snapshot,'total',grand_total) as before_state
   from public.invoices i where k='invoice' and company_id=cid and customer_id=party and billing_period_start>m
    and status='draft' and automatic_calculation and finalized_at is null and approval_finalized_at is null and not coalesce(invoice_seal_frozen,false)
    and not exists(select 1 from public.invoice_approvals a where a.invoice_id=i.id and a.status='approved')
   union all
   select period_start,jsonb_build_object('id',id,'snapshot',snapshot,'total',net_amount)
   from public.payment_certificates where k='payment_certificate' and company_id=cid and partner_company_id=party and period_start>m
    and status='draft' and automatic_calculation and finalized_at is null
   order by 1
  loop
   future_after:=document_adjustment_private.source(cid,k,party,future.month);
   insert into document_adjustment_private.scope_versions(company_id,kind,party_id,month,version)
    values(cid,k,party,future.month,1) on conflict(company_id,kind,party_id,month)
    do update set version=document_adjustment_private.scope_versions.version+1;
   future_states:=future_states||jsonb_build_array(jsonb_build_object('month',future.month,'before',future.before_state,'after',future_after));
  end loop;
 end if;
 receipt:=jsonb_build_object('request',p_command,'applied',true,'version',current_version,'entry_id',oid,
  'preview_token',p_preview_token,'result_total_yen',prev.result_total);
 insert into document_adjustment_private.commands(command_id,actor_id,company_id,request,receipt)
  values((p_command->>'command_id')::uuid,actor,cid,p_command,receipt);
 insert into document_adjustment_private.audit(command_id,actor_id,company_id,before_state,after_state)
  values((p_command->>'command_id')::uuid,actor,cid,src,after_source||jsonb_build_object('receipt',receipt,'future_drafts',future_states));
 return receipt;
end $body$;
revoke all on function public.apply_trade_document_adjustment(jsonb,uuid) from public,anon;
grant execute on function public.apply_trade_document_adjustment(jsonb,uuid) to authenticated;

-- Retrying lookup rechecks current company permissions; revoked users do not
-- regain access through an old command receipt. Never treat null as saved.
create function public.lookup_trade_document_adjustment(p_company_id uuid,p_command_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $body$
declare c document_adjustment_private.commands%rowtype;
begin
 perform private.require_reauthentication_session();
 select * into c from document_adjustment_private.commands where command_id=p_command_id
  and company_id=p_company_id and actor_id=auth.uid();
 if not found then return null;end if;
 perform document_adjustment_private.authorize(p_company_id,c.request->>'kind',(c.request->>'party_id')::uuid);
 return c.receipt;
end $body$;
revoke all on function public.lookup_trade_document_adjustment(uuid,uuid) from public,anon;
grant execute on function public.lookup_trade_document_adjustment(uuid,uuid) to authenticated;
commit;
