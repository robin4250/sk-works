-- REVIEW CANDIDATE ONLY. Not a deployment or completed registration API.
-- Source refresh integration and access-contract validation must pass before rollout.
begin;
create schema if not exists document_adjustment_private;
revoke all on schema document_adjustment_private from public, anon, authenticated, service_role;

create table document_adjustment_private.rollout (
 company_id uuid primary key references public.companies(id),
 enabled boolean not null default false,
 updated_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.operation_events (
 id bigint generated always as identity primary key,
 company_id uuid not null references public.companies(id),
 actor_id uuid not null,session_id uuid not null,
 action text not null check(action in ('rollout_change','preview_cleanup')),
 reason text not null check(length(btrim(reason)) between 5 and 500),
 previous_enabled boolean,enabled boolean,details jsonb not null default '{}',
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.templates (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 kind text not null check(kind in ('invoice','payment_certificate')),
 party_id uuid not null,
 recurrence text not null check(recurrence in ('once','monthly')),
 created_by uuid not null,
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.template_versions (
 template_id uuid not null references document_adjustment_private.templates(id),
 version bigint not null check(version>0),
 effective_month date not null check(extract(day from effective_month)=1),
 title text not null check(length(btrim(title)) between 1 and 120),
 sign text not null check(sign in ('plus','minus')),
 amount_yen bigint not null check(amount_yen between 1 and 2147483647),
 calculation_mode text not null check(calculation_mode in ('before_charges','settlement_yen')),
 site_id uuid,
 stopped boolean not null default false,
 actor_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(template_id,version)
);
create table document_adjustment_private.scope_versions (
 company_id uuid not null references public.companies(id),
 kind text not null check(kind in ('invoice','payment_certificate')),
 party_id uuid not null,
 month date not null check(extract(day from month)=1),
 version bigint not null default 0 check(version>=0),
 primary key(company_id,kind,party_id,month)
);
create table document_adjustment_private.occurrences (
 id uuid primary key default gen_random_uuid(),
 template_id uuid not null references document_adjustment_private.templates(id),
 month date not null check(extract(day from month)=1),
 document_id uuid,
 template_version bigint not null,
 override jsonb,
 canceled boolean not null default false,
 finalized_snapshot jsonb,
 unique(template_id,month),
 foreign key(template_id,template_version) references document_adjustment_private.template_versions(template_id,version)
);
create table document_adjustment_private.commands (
 command_id uuid primary key,
 actor_id uuid not null,
 company_id uuid not null references public.companies(id),
 request jsonb not null,
 receipt jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create table document_adjustment_private.audit (
 id bigint generated always as identity primary key,
 command_id uuid not null references document_adjustment_private.commands(command_id),
 actor_id uuid not null,
 company_id uuid not null,
 before_state jsonb,
 after_state jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
do $body$ declare n text; begin
 foreach n in array array['rollout','operation_events','templates','template_versions','scope_versions','occurrences','commands','audit'] loop
  execute format('alter table document_adjustment_private.%I enable row level security',n);
  execute format('revoke all on table document_adjustment_private.%I from public,anon,authenticated,service_role',n);
 end loop;
end $body$;
revoke all on all sequences in schema document_adjustment_private from public,anon,authenticated,service_role;

-- Every projection writer takes company -> rollout gate -> finance scope ->
-- document row. Exclusive OFF waits for all in-flight shared writers to commit;
-- a writer starting after OFF observes false before modifying its ledger.
create function document_adjustment_private.lock_rollout_gate(p_company uuid,p_exclusive boolean default false)
returns void language plpgsql security definer set search_path='' as $body$
begin
 perform 1 from public.companies where id=p_company for share;
 if not found then raise exception '会社情報を確認できません';end if;
 if p_exclusive then
  perform pg_advisory_xact_lock(hashtextextended('document-adjustment-rollout:'||p_company::text,0));
 else
  perform pg_advisory_xact_lock_shared(hashtextextended('document-adjustment-rollout:'||p_company::text,0));
 end if;
end $body$;
revoke all on function document_adjustment_private.lock_rollout_gate(uuid,boolean) from public,anon,authenticated,service_role;

-- Pure arithmetic only. Saved baseline and rates come from the real source,
-- never caller input. Applying a negative pre-charge entry recalculates the
-- original group's welfare/tax rounding; negating an independently rounded
-- positive calculation would be incorrect at half-yen boundaries.
create function document_adjustment_private.charge_delta(
 p_base bigint,p_delta bigint,p_welfare numeric,p_tax numeric
) returns jsonb language plpgsql immutable set search_path='' as $body$
declare old_w bigint;new_w bigint;old_t bigint;new_t bigint;
begin
 if p_base is null or p_delta is null or p_welfare is null or p_tax is null
    or p_welfare<0 or p_welfare>100 or p_tax<0 or p_tax>100 then
  raise exception '保存済みの計算設定を確認できません';
 end if;
 old_w:=round(p_base*p_welfare/100);new_w:=round((p_base+p_delta)*p_welfare/100);
 old_t:=round((p_base+old_w)*p_tax/100);new_t:=round((p_base+p_delta+new_w)*p_tax/100);
 return jsonb_build_object('base_delta_yen',p_delta,
  'welfare_delta_yen',new_w-old_w,'tax_delta_yen',new_t-old_t,
  'total_delta_yen',p_delta+new_w-old_w+new_t-old_t);
end $body$;
revoke all on function document_adjustment_private.charge_delta(bigint,bigint,numeric,numeric) from public,anon,authenticated,service_role;

create function document_adjustment_private.ledger_items(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language sql stable security definer set search_path='' as $body$
 select coalesce(jsonb_agg(jsonb_build_object(
  'template_id',t.id,'template_version',v.version,'entry_id',o.id,
  'title',coalesce(o.override->>'title',v.title),
  'sign',coalesce(o.override->>'sign',v.sign),
  'amount_yen',coalesce((o.override->>'amount_yen')::bigint,v.amount_yen),
  'calculation_mode',coalesce(o.override->>'calculation_mode',v.calculation_mode),
  'site_id',coalesce(o.override->>'site_id',v.site_id::text),
  'recurrence',t.recurrence,'month',p_month
 ) order by t.created_at,t.id),'[]'::jsonb)
 from document_adjustment_private.templates t
 join lateral (
  select x.* from document_adjustment_private.template_versions x
  where x.template_id=t.id and x.effective_month<=p_month
   and (t.recurrence='monthly' or x.effective_month=p_month)
  order by x.effective_month desc,x.version desc limit 1
 ) v on not v.stopped
 left join document_adjustment_private.occurrences o on o.template_id=t.id and o.month=p_month
 where t.company_id=p_company and t.kind=p_kind and t.party_id=p_party
  and not coalesce(o.canceled,false)
$body$;
revoke all on function document_adjustment_private.ledger_items(uuid,text,uuid,date) from public,anon,authenticated,service_role;
create function document_adjustment_private.active_items(p_company uuid,p_kind text,p_party uuid,p_month date)
returns jsonb language sql stable security definer set search_path='' as $body$
 select case when exists(select 1 from document_adjustment_private.rollout where company_id=p_company and enabled)
 then document_adjustment_private.ledger_items(p_company,p_kind,p_party,p_month) else '[]'::jsonb end
$body$;
revoke all on function document_adjustment_private.active_items(uuid,text,uuid,date) from public,anon,authenticated,service_role;

create function document_adjustment_private.ensure_occurrences(p_company uuid,p_kind text,p_party uuid,p_month date)
returns void language plpgsql security definer set search_path='' as $body$
begin
 insert into document_adjustment_private.occurrences(template_id,month,template_version)
 select (x->>'template_id')::uuid,p_month,(x->>'template_version')::bigint
 from jsonb_array_elements(document_adjustment_private.active_items(p_company,p_kind,p_party,p_month)) x
 on conflict(template_id,month) do update set template_version=excluded.template_version
 where document_adjustment_private.occurrences.override is null
   and document_adjustment_private.occurrences.finalized_snapshot is null;
end $body$;
revoke all on function document_adjustment_private.ensure_occurrences(uuid,text,uuid,date) from public,anon,authenticated,service_role;

create function document_adjustment_private.bind_occurrences(p_company uuid,p_kind text,p_party uuid,p_month date,p_document uuid)
returns void language plpgsql security definer set search_path='' as $body$
begin
 if p_document is null then return;end if;
 update document_adjustment_private.occurrences o set document_id=p_document
 from document_adjustment_private.templates t where t.id=o.template_id and t.company_id=p_company
  and t.kind=p_kind and t.party_id=p_party and o.month=p_month and o.document_id is null;
end $body$;
revoke all on function document_adjustment_private.bind_occurrences(uuid,text,uuid,date,uuid) from public,anon,authenticated,service_role;

create function document_adjustment_private.append_only() returns trigger
language plpgsql set search_path='' as $body$ begin raise exception '監査・操作履歴は変更できません';end $body$;
revoke all on function document_adjustment_private.append_only() from public,anon,authenticated,service_role;
create trigger audit_append_only before update or delete on document_adjustment_private.audit
 for each row execute function document_adjustment_private.append_only();
create trigger commands_append_only before update or delete on document_adjustment_private.commands
 for each row execute function document_adjustment_private.append_only();
create trigger template_versions_append_only before update or delete on document_adjustment_private.template_versions
 for each row execute function document_adjustment_private.append_only();
create trigger operation_events_append_only before update or delete on document_adjustment_private.operation_events
 for each row execute function document_adjustment_private.append_only();
create index operation_events_company_time on document_adjustment_private.operation_events(company_id,id desc);
create index adjustment_templates_scope on document_adjustment_private.templates(company_id,kind,party_id);
create index adjustment_occurrences_document on document_adjustment_private.occurrences(document_id);
create index adjustment_commands_preview on document_adjustment_private.commands((receipt->>'preview_token'));

create function document_adjustment_private.capture_finalized() returns trigger
language plpgsql security definer set search_path='' as $body$
declare d jsonb:=to_jsonb(new);k text;
begin
 k:=case tg_table_name when 'invoices' then 'invoice' else 'payment_certificate' end;
 if d->>'status'<>'draft' or d->>'finalized_at' is not null or d->>'approval_finalized_at' is not null then
  update document_adjustment_private.occurrences o set finalized_snapshot=d->'snapshot'
   from document_adjustment_private.templates t where t.id=o.template_id and t.kind=k
    and t.company_id=(d->>'company_id')::uuid and o.document_id=(d->>'id')::uuid
    and o.finalized_snapshot is null;
 end if;
 return new;
end $body$;
revoke all on function document_adjustment_private.capture_finalized() from public,anon,authenticated,service_role;
create trigger document_adjustments_finalize_invoice after update on public.invoices
 for each row execute function document_adjustment_private.capture_finalized();
create trigger document_adjustments_finalize_certificate after update on public.payment_certificates
 for each row execute function document_adjustment_private.capture_finalized();

-- Preview evaluates changes against a freshly refreshed source snapshot.
-- It does not mutate saved totals or accept client-supplied rates.
create function document_adjustment_private.preview_delta(
 p_kind text,p_snapshot jsonb,p_old jsonb,p_new jsonb
) returns jsonb language plpgsql immutable set search_path='' as $body$
declare s jsonb;g jsonb;old_amount bigint;new_amount bigint;base bigint;
 w numeric;t numeric;delta_base bigint:=0;delta_w bigint:=0;delta_t bigint:=0;
 final_old bigint;final_new bigint;d jsonb;site text;
begin
 if jsonb_typeof(p_old)<>'array' or jsonb_typeof(p_new)<>'array' then
  raise exception '調整明細を確認できません';end if;
 if p_kind='invoice' then
  for site in select distinct x->>'site_id' from jsonb_array_elements(p_old||p_new) x
    where x->>'calculation_mode'='before_charges'
  loop
   select x into s from jsonb_array_elements(p_snapshot->'sites') x where x->>'site_id'=site;
   if s is null then raise exception '計算対象の現場を確認できません';end if;
   select coalesce(sum((x->>'amount')::bigint),0) into old_amount
    from jsonb_array_elements(s->'lines') x where x->>'work_content'='（法定福利費）';
   base:=(s->>'subtotal')::bigint-old_amount;
   w:=(s->>'welfare_rate_bps')::numeric/100;t:=(p_snapshot->>'tax_rate_bps')::numeric/100;
   select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
    into old_amount from jsonb_array_elements(p_old) x where x->>'site_id'=site and x->>'calculation_mode'='before_charges';
   select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
    into new_amount from jsonb_array_elements(p_new) x where x->>'site_id'=site and x->>'calculation_mode'='before_charges';
   d:=document_adjustment_private.charge_delta(base,new_amount-old_amount,w,t);
   delta_base:=delta_base+(d->>'base_delta_yen')::bigint;
   delta_w:=delta_w+(d->>'welfare_delta_yen')::bigint;
   delta_t:=delta_t+(d->>'tax_delta_yen')::bigint;
  end loop;
 elsif p_kind='payment_certificate' then
  select coalesce(sum((x->>'amount_yen')::bigint),0) into base
   from jsonb_array_elements(p_snapshot->'calculation_rows') x
   where x->>'work_content' not in ('福利厚生費','消費税');
  w:=(p_snapshot->>'welfare_rate')::numeric;t:=(p_snapshot->>'tax_rate')::numeric;
  select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
   into old_amount from jsonb_array_elements(p_old) x where x->>'calculation_mode'='before_charges';
  select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
   into new_amount from jsonb_array_elements(p_new) x where x->>'calculation_mode'='before_charges';
  d:=document_adjustment_private.charge_delta(base,new_amount-old_amount,w,t);
  delta_base:=(d->>'base_delta_yen')::bigint;delta_w:=(d->>'welfare_delta_yen')::bigint;delta_t:=(d->>'tax_delta_yen')::bigint;
 else raise exception '帳票区分を確認できません';end if;
 select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
  into final_old from jsonb_array_elements(p_old) x where x->>'calculation_mode'='settlement_yen';
 select coalesce(sum((x->>'amount_yen')::bigint*case when x->>'sign'='minus' then -1 else 1 end),0)
  into final_new from jsonb_array_elements(p_new) x where x->>'calculation_mode'='settlement_yen';
 return jsonb_build_object('base_delta_yen',delta_base,'welfare_delta_yen',delta_w,
  'tax_delta_yen',delta_t,'settlement_delta_yen',final_new-final_old,
  'total_delta_yen',delta_base+delta_w+delta_t+final_new-final_old);
end $body$;
revoke all on function document_adjustment_private.preview_delta(text,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
commit;
