from pathlib import Path
import json,hashlib,re
root=Path(__file__).parent
pins=json.loads((root/'source-pins.json').read_text())
force=next(x['definition'] for x in pins if x['signature']=='force_manage_attendance(text,jsonb)')
roster=next(x['definition'] for x in pins if x['signature'].startswith('attendance_admin_override_private.permit_roster'))
prefix='''-- REVIEW ONLY. Default OFF, no activation or employee changes.
-- Install after the audited attendance override. Does not change signature/normal financial writers.
begin;
do $pins$ begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.force_manage_attendance(text,jsonb)') and md5(prosrc)='0e5cee91af53cc09e212e620394785f6' and pg_get_userbyid(proowner)='postgres' and prosecdef) then raise exception 'management_allowance_force_source_mismatch';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('attendance_admin_override_private.permit_roster(text,jsonb,jsonb)') and md5(prosrc)='e77df23eee8e665c428923d9c12b27ea') then raise exception 'management_allowance_roster_source_mismatch';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('company_checkout_allowance_private.registered_item(uuid,uuid,jsonb)') and md5(prosrc)='8522fba99b37015028f92e2560b026d1') then raise exception 'management_allowance_registry_source_mismatch';end if;
end $pins$;
create schema management_registered_allowance_private;
revoke all on schema management_registered_allowance_private from public,anon,authenticated,service_role;
create table management_registered_allowance_private.rollout(company_id uuid primary key references public.companies(id),enabled boolean not null default false);
alter table management_registered_allowance_private.rollout enable row level security;
revoke all on management_registered_allowance_private.rollout from public,anon,authenticated,service_role;
create function management_registered_allowance_private.enabled(cid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select attendance_admin_override_private.enabled(cid) and exists(select 1 from management_registered_allowance_private.rollout where company_id=cid and enabled)
$$;
create function management_registered_allowance_private.check_payload(cid uuid,action_name text,items jsonb) returns void language plpgsql stable security definer set search_path='' as $$
declare x jsonb;
begin
 for x in select value from jsonb_array_elements(items) loop
  if x?'company_allowance_selections' or x?'company_allowance_legacy_labels' then
   if not management_registered_allowance_private.enabled(cid) then raise sqlstate '42501' using message='management_registered_allowances_disabled';end if;
   if action_name<>'upsert' or coalesce(x->>'mode','work')<>'work' then raise sqlstate '22023' using message='management_allowances_require_work';end if;
   if x?'company_allowance_selections' and (x->'company_allowance_selections'='null'::jsonb or jsonb_typeof(x->'company_allowance_selections') is distinct from 'object') then raise sqlstate '22023' using message='management_allowances_use_explicit_empty_selection';end if;
   if x?'company_allowance_legacy_labels' and jsonb_typeof(x->'company_allowance_legacy_labels') not in('string','null') then raise sqlstate '22023' using message='management_allowance_legacy_text_invalid';end if;
  end if;
 end loop;
end $$;

-- A plan is derived from the private BEFORE audit, never from caller-supplied old snapshots.
create function management_registered_allowance_private.plan(cid uuid,wid uuid,day_value date,site_value uuid,item jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare context jsonb;old_worker jsonb;old_report jsonb;old_entry jsonb;old_count integer;choices jsonb;legacy text;label text;
 selected_names text[];free_names text[];names text[];prior_receipt uuid;changed boolean;
begin
 if not management_registered_allowance_private.enabled(cid) then return null;end if;
 context:=attendance_admin_override_private.current_context();
 if context is null or context->>'company_id'<>cid::text or context->>'action'<>'upsert'
 or not exists(select 1 from jsonb_array_elements(context->'items') x where x=item and x->>'worker_id'=wid::text and x->>'date'=day_value::text and x->>'site_id'=site_value::text) then raise sqlstate '42501' using message='management_allowance_exact_operation_required';end if;
 select count(*) into old_count from attendance_admin_override_private.operations o,
 lateral jsonb_array_elements(o.before_state->'reports') d,lateral jsonb_array_elements(d->'roster') w
 where o.id=(context->>'operation_id')::uuid and d#>>'{report,company_id}'=cid::text and d#>>'{report,site_id}'=site_value::text and d#>>'{report,report_date}'=day_value::text and w->>'worker_id'=wid::text;
 if old_count>1 then raise sqlstate '55000' using message='management_allowance_ambiguous_previous_report';end if;
 select d->'report',w into old_report,old_worker from attendance_admin_override_private.operations o,
 lateral jsonb_array_elements(o.before_state->'reports') d,lateral jsonb_array_elements(d->'roster') w
 where o.id=(context->>'operation_id')::uuid and d#>>'{report,company_id}'=cid::text and d#>>'{report,site_id}'=site_value::text and d#>>'{report,report_date}'=day_value::text and w->>'worker_id'=wid::text;
 if old_worker is not null then
  select a into old_entry from attendance_admin_override_private.operations o,
   lateral jsonb_array_elements(o.before_state->'reports') d,lateral jsonb_array_elements(d->'linked_entries') a
   where o.id=(context->>'operation_id')::uuid and d#>>'{report,id}'=old_report->>'id' and a->>'worker_id'=wid::text
    and a->>'company_id'=cid::text and a->>'work_date'=day_value::text and a->>'company_allowance_receipt_id' is not null limit 1;
  prior_receipt:=nullif(old_entry->>'company_allowance_receipt_id','')::uuid;
 end if;
 choices:=nullif(old_worker->'company_allowance_selections','null'::jsonb);
 if item?'company_allowance_selections' then choices:=item->'company_allowance_selections';end if;
 changed:=choices is distinct from nullif(old_worker->'company_allowance_selections','null'::jsonb);
 if changed and not item?'company_allowance_legacy_labels' then raise sqlstate '22023' using message='management_allowance_explicit_legacy_labels_required';end if;
 if changed then choices:=company_checkout_allowance_private.normalize_choices(cid,wid,choices);prior_receipt:=null;end if;
 if choices is not null and (choices->>'contract_version' is distinct from '1' or jsonb_typeof(choices->'items') is distinct from 'array') then raise sqlstate '55000' using message='management_allowance_previous_selection_invalid';end if;
 if item?'company_allowance_legacy_labels' then legacy:=item->>'company_allowance_legacy_labels';
 elsif old_worker is not null and (choices is not null or old_worker->>'company_allowance_legacy_labels' is not null) then legacy:=old_worker->>'company_allowance_legacy_labels';
 else select string_agg(value,E'\\n') into legacy from jsonb_array_elements_text(coalesce(item->'allowance_names','[]'::jsonb));end if;
 if length(coalesce(legacy,''))>1048576 then raise sqlstate '22023' using message='management_allowance_legacy_text_exceeds_range';end if;
 if choices is null then
  if prior_receipt is not null then raise sqlstate '55000' using message='management_allowance_receipt_without_selection_requires_review';end if;
  if item?'company_allowance_legacy_labels' or legacy is not null then
   select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>''),'{}') into names from unnest(string_to_array(coalesce(legacy,''),E'\\n')) x;
   label:=nullif(array_to_string(names,E'\\n'),'');
  else
   select array_agg(value) into names from jsonb_array_elements_text(coalesce(item->'allowance_names','[]'::jsonb));
   label:=nullif(array_to_string(names,'・'),'');legacy:=null;
  end if;
 else
  select coalesce(array_agg(x->>'name_snapshot' order by ord),'{}') into selected_names from jsonb_array_elements(choices->'items') with ordinality t(x,ord);
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>''),'{}') into free_names from unnest(string_to_array(coalesce(legacy,''),E'\\n')) x;
  select coalesce(array_agg(distinct x order by x),'{}') into names from unnest(selected_names||free_names) x;
  if not changed and not item?'company_allowance_legacy_labels' and old_worker is not null then label:=old_worker->>'allowance_label';
  else label:=nullif(array_to_string(names,E'\\n'),'');end if;
  if changed or prior_receipt is null then
   perform company_checkout_allowance_private.validate_labels(cid,wid,label,choices,legacy);
  end if;
 end if;
 return jsonb_build_object('choices',choices,'legacy_labels',legacy,'label',label,'names',coalesce(to_jsonb(names),'[]'::jsonb),
  'prior_receipt_id',prior_receipt,'prior_report_id',old_report->>'id','changed',changed);
end $$;

create function management_registered_allowance_private.matches(rid uuid,wid uuid,target jsonb,item jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
declare r public.daily_reports%rowtype;p jsonb;
begin
 select * into r from public.daily_reports where id=rid;
 if r.id is null or not management_registered_allowance_private.enabled(r.company_id) then return false;end if;
 p:=management_registered_allowance_private.plan(r.company_id,wid,r.report_date,r.site_id,item);
 return target->'company_allowance_selections' is not distinct from coalesce(p->'choices','null'::jsonb)
  and target->'company_allowance_legacy_labels' is not distinct from coalesce(p->'legacy_labels','null'::jsonb)
  and target->'allowance_label' is not distinct from coalesce(p->'label','null'::jsonb);
end $$;

-- This is an actual administrative authorization receipt, explicitly NOT a handwritten-signature receipt.
-- Existing capture_report retains its both-real-signatures requirement unchanged.
create function management_registered_allowance_private.capture(rid uuid,wid uuid,p jsonb) returns uuid language plpgsql volatile security definer set search_path='' as $$
declare context jsonb;r public.daily_reports%rowtype;w public.daily_report_workers%rowtype;receipt company_checkout_allowance_private.receipts%rowtype;
 item jsonb;registered jsonb;items jsonb:='[]';body jsonb;digest text;answer uuid;
begin
 context:=attendance_admin_override_private.current_context();
 select * into r from public.daily_reports where id=rid;
 select * into w from public.daily_report_workers where report_id=rid and worker_id=wid;
 if context is null or r.id is null or r.status<>'draft' or r.representative_signature_json is not null or r.supervisor_signature_json is not null or context->>'company_id'<>r.company_id::text or not (context->'report_ids')?rid::text
 or w.worker_id is null or to_jsonb(w)->'company_allowance_selections' is distinct from coalesce(p->'choices','null'::jsonb)
 or to_jsonb(w)->'company_allowance_legacy_labels' is distinct from coalesce(p->'legacy_labels','null'::jsonb)
 or to_jsonb(w)->'allowance_label' is distinct from coalesce(p->'label','null'::jsonb) then raise sqlstate '42501' using message='management_allowance_exact_saved_row_required';end if;
 if w.company_allowance_selections is null then return null;end if;
 if p->>'prior_receipt_id' is not null then
  select * into receipt from company_checkout_allowance_private.receipts where id=(p->>'prior_receipt_id')::uuid;
  if receipt.id is null or receipt.company_id<>r.company_id or receipt.worker_id<>wid or receipt.report_id<>rid or receipt.work_date<>r.report_date
   or receipt.snapshot->>'contract_version'<>'1' or receipt.snapshot->>'work_date'<>r.report_date::text
   or receipt.snapshot_sha256 is distinct from encode(sha256(convert_to(receipt.snapshot::text,'UTF8')),'hex') then raise sqlstate '55000' using message='management_allowance_previous_receipt_scope_changed';end if;
  if jsonb_array_length(receipt.snapshot->'items')<>jsonb_array_length(w.company_allowance_selections->'items')
   or exists(select 1 from jsonb_array_elements(w.company_allowance_selections->'items') x where not exists(
    select 1 from jsonb_array_elements(receipt.snapshot->'items') y where y->>'origin'=x->>'origin' and (y->>'id')::uuid=(x->>'id')::uuid
    and y->'generation' is not distinct from x->'generation' and y->'registration_version'=x->'registration_version'
    and y->>'name'=x->>'name_snapshot' and y->>'unit'=x->>'unit')) then raise sqlstate '55000' using message='management_allowance_previous_receipt_identity_changed';end if;
  return receipt.id;
 end if;
 perform company_checkout_allowance_private.validate_labels(r.company_id,wid,w.allowance_label,w.company_allowance_selections,w.company_allowance_legacy_labels);
 for item in select value from jsonb_array_elements(w.company_allowance_selections->'items') order by value->>'origin',value->>'id' loop
  registered:=company_checkout_allowance_private.registered_item(r.company_id,wid,item);items:=items||jsonb_build_array(registered);
 end loop;
 body:=jsonb_build_object('contract_version',1,'work_date',r.report_date,'items',items,
  'authority',jsonb_build_object('kind','attendance_management','operation_id',context->'operation_id','actor_id',context->'actor_id','session_id',context->'session_id'));
 digest:=encode(sha256(convert_to(body::text,'UTF8')),'hex');
 insert into company_checkout_allowance_private.receipts(company_id,worker_id,report_id,work_date,snapshot,snapshot_sha256,captured_by)
 values(r.company_id,wid,rid,r.report_date,body,digest,auth.uid()) on conflict(company_id,worker_id,report_id,work_date,snapshot_sha256) do nothing;
 select id into answer from company_checkout_allowance_private.receipts where company_id=r.company_id and worker_id=wid and report_id=rid and work_date=r.report_date and snapshot_sha256=digest and snapshot=body;
 if answer is null then raise sqlstate '55000' using message='management_allowance_receipt_unavailable';end if;
 return answer;
end $$;
revoke all on all functions in schema management_registered_allowance_private from public,anon,authenticated,service_role;
'''
options='''
create function public.read_management_company_allowance_options(p_worker_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid;actor uuid;wid uuid;labels jsonb;label jsonb;candidate jsonb;validated jsonb;items jsonb;answer jsonb:='[]';typ text;
begin
 select company_id into cid from public.company_members where user_id=auth.uid() limit 1;
 actor:=attendance_admin_override_private.require_manager(cid);
 if not management_registered_allowance_private.enabled(cid) then raise sqlstate '42501' using message='management_registered_allowances_disabled';end if;
 if p_worker_ids is null or cardinality(p_worker_ids) not between 1 and 500 or cardinality(p_worker_ids)<>(select count(distinct x) from unnest(p_worker_ids) x)
 or exists(select 1 from unnest(p_worker_ids) x where x is null or not exists(select 1 from public.workers w where w.id=x and w.company_id=cid and w.status='active')) then raise sqlstate '42501' using message='management_allowance_worker_scope_invalid';end if;
 labels:=public.read_company_registered_allowance_labels(cid);
 foreach wid in array p_worker_ids loop
  items:='[]';select pay_type into typ from public.worker_payroll_settings where company_id=cid and worker_id=wid;
  if typ is not null then
   for label in select value from jsonb_array_elements(labels->'items') loop
    if label->>'unit' not in('day','hour') or label->>'id' is null or label->>'registration_version' is null
     or(label->>'origin'='company_common' and label->>'payroll_type'<>typ) then continue;end if;
    candidate:=jsonb_build_object('origin',label->'origin','id',label->'id','generation',label->'generation','registration_version',label->'registration_version','name_snapshot',label->'name','unit',label->'unit');
    validated:=company_checkout_allowance_private.registered_item(cid,wid,candidate);
    items:=items||jsonb_build_array(jsonb_build_object('origin',validated->'origin','id',validated->'id','generation',validated->'generation','registration_version',validated->'registration_version'));
   end loop;
  end if;
  answer:=answer||jsonb_build_array(jsonb_build_object('worker_id',wid,'items',items));
 end loop;
 return jsonb_build_object('contract_version',1,'company_id',cid,'labels',labels,'workers',answer);
end $$;
revoke all on function public.read_management_company_allowance_options(uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.read_management_company_allowance_options(uuid[]) to authenticated;
'''
# Restrict typed-field writes to the exact server-computed plan while retaining all original scope checks.
old="  and nullif(target->>'allowance_label','') is not distinct from nullif((select string_agg(value,'・') from jsonb_array_elements_text(coalesce(item->'allowance_names','[]'::jsonb))),'');"
new="  and case when management_registered_allowance_private.enabled(r.company_id) then management_registered_allowance_private.matches(rid,wid,target,item) else nullif(target->>'allowance_label','') is not distinct from nullif((select string_agg(value,'・') from jsonb_array_elements_text(coalesce(item->'allowance_names','[]'::jsonb))),'') end;"
assert old in roster;roster=roster.replace(old,new)
force=force.replace('  v_clock_delete_id uuid;','  v_clock_delete_id uuid;\n  v_allowance_plan jsonb;\n  v_registered_receipt uuid;')
force=force.replace('  perform shared_daily_report_private.lock_management_batch(v_company_id,p_action,p_items);','  perform management_registered_allowance_private.check_payload(v_company_id,p_action,p_items);\n  perform shared_daily_report_private.lock_management_batch(v_company_id,p_action,p_items);')
needle='    -- Keep correction audit snapshots, but detach FK so forced deletion can proceed.'
assert needle in force
force=force.replace(needle,"    v_allowance_plan:=null;v_registered_receipt:=null;\n    if p_action='upsert' and v_mode='work' then\n      v_allowance_plan:=management_registered_allowance_private.plan(v_company_id,v_worker_id,v_date,v_site_id,v_item);\n    end if;\n\n"+needle)
needle='      allowance_label,\n      work_category\n    ) values ('
assert needle in force;force=force.replace(needle,'      allowance_label,\n      work_category,\n      company_allowance_selections,\n      company_allowance_legacy_labels\n    ) values (')
oldlabel="""      nullif(array_to_string(
        array(
          select jsonb_array_elements_text(
            coalesce(v_item->'allowance_names','[]'::jsonb)
          )
        ),
        '・'
      ),''),
      'day'
"""
newlabel="""      case when v_allowance_plan is not null then v_allowance_plan->>'label' else nullif(array_to_string(
        array(select jsonb_array_elements_text(coalesce(v_item->'allowance_names','[]'::jsonb))), '・'), '') end,
      'day',
      nullif(v_allowance_plan->'choices','null'::jsonb),
      v_allowance_plan->>'legacy_labels'
"""
assert oldlabel in force;force=force.replace(oldlabel,newlabel)
force=force.replace('      work_category = excluded.work_category;','      work_category = excluded.work_category,\n      company_allowance_selections = excluded.company_allowance_selections,\n      company_allowance_legacy_labels = excluded.company_allowance_legacy_labels;')
force=force.replace('    insert into public.attendance_entries(','    if v_allowance_plan is not null then\n      v_registered_receipt:=management_registered_allowance_private.capture(v_report_id,v_worker_id,v_allowance_plan);\n    end if;\n\n    insert into public.attendance_entries(')
force=force.replace('      source_report_id\n    ) values (','      source_report_id,\n      company_allowance_receipt_id\n    ) values (')
oldnames="""      array(
        select jsonb_array_elements_text(
          coalesce(v_item->'allowance_names','[]'::jsonb)
        )
      ),"""
newnames="""      array(select jsonb_array_elements_text(case when v_allowance_plan is not null then v_allowance_plan->'names' else coalesce(v_item->'allowance_names','[]'::jsonb) end)),"""
assert oldnames in force;force=force.replace(oldnames,newnames)
force=force.replace("      'day',\n      v_report_id\n    );","      'day',\n      v_report_id,\n      v_registered_receipt\n    );")
(root/'management-registered-allowances.sql.review-only').write_text(prefix+options+'\n'+roster.rstrip().rstrip(';')+';\n'+force.rstrip().rstrip(';')+';\ncommit;\n')
print({'bytes':(root/'management-registered-allowances.sql.review-only').stat().st_size,'force_patch_verified':True})
