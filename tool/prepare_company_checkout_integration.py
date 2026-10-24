#!/usr/bin/env python3
"""Offline source-bound review-unit generator; never connects to a database."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tool/fixtures/company_checkout_actual_sources.json'

def body(definition):
    found = re.search(r'\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$', definition, re.I)
    if not found: raise ValueError('Function body delimiter unavailable')
    return found.group(2)

def once(source, old, new):
    if source.count(old) != 1: raise ValueError('Source anchor not unique: '+old[:80])
    return source.replace(old, new)

def regex_once(source, pattern, replace):
    result, count = re.subn(pattern, replace, source)
    if count != 1: raise ValueError('Source regex not unique: '+pattern)
    return result

def fq(signature):
    return signature if '.' in signature.split('(')[0] else 'public.'+signature

def literal(value): return "'"+value.replace("'", "''")+"'"

def draft_patch(source):
    source = once(source, '  v_worker_id uuid;', '''  v_worker_id uuid;
  checkout_previous_choices jsonb; checkout_previous_labels jsonb;
  checkout_previous_legacy_labels jsonb; checkout_choices jsonb; checkout_legacy_labels text;
  checkout_previous_basis jsonb; checkout_prior_report_id uuid; checkout_had_choices boolean:=false;''')
    destination="r.route_assignment_id is not distinct from p_route_assignment_id" if 'p_route_assignment_id uuid' in source else 'true'
    source=regex_once(source,r'(?m)^  if v_report_id is not null then',"""  select r.id into checkout_prior_report_id from public.daily_reports r where r.company_id=v_company_id
    and ((v_report_id is not null and r.id=v_report_id) or (v_report_id is null
      and r.site_id is not distinct from p_site_id and r.report_date=p_report_date and """+destination+"""))
    limit 1 for update;
  checkout_previous_basis:=company_checkout_allowance_private.report_basis(checkout_prior_report_id);
  select exists(select 1 from public.daily_report_workers where report_id=checkout_prior_report_id
    and company_allowance_selections is not null) into checkout_had_choices;
  if v_report_id is not null then""")
    # Preserve the original destination clear for untyped reports. Only typed
    # old/new payloads defer approval invalidation to the complete basis compare.
    for field in ['representative_signature_json','representative_signer_name','supervisor_signature_json','supervisor_signer_name']:
        source=source.replace('        '+field+'=null,', '        '+field+'=case when checkout_had_choices or exists('
            "select 1 from jsonb_array_elements(coalesce(p_workers,'[]'::jsonb)) x where x?'company_allowance_selections') then "
            +field+' else null end,')
    source = regex_once(source, r'  delete from public\.daily_report_workers\s+where report_id\s*=\s*v_report_id;',
        '''  select coalesce(jsonb_object_agg(worker_id::text,company_allowance_selections),'{}'),
    coalesce(jsonb_object_agg(worker_id::text,allowance_label),'{}'),
    coalesce(jsonb_object_agg(worker_id::text,company_allowance_legacy_labels),'{}')
    into checkout_previous_choices,checkout_previous_labels,checkout_previous_legacy_labels
    from public.daily_report_workers where report_id=v_report_id;
  delete from public.daily_report_workers where report_id=v_report_id;''')
    source = once(source, "    ) > 3 then" if "    ) > 3 then" in source else ") > 3 then",
        ("    ) > 3" if "    ) > 3 then" in source else ") > 3")+" and not (v_worker?'company_allowance_selections') and nullif(checkout_previous_choices->v_worker_id::text,'null'::jsonb) is null then")
    source = regex_once(source, r'    insert into public\.daily_report_workers\(', '''    checkout_choices:=case when v_worker?'company_allowance_selections' then v_worker->'company_allowance_selections'
      else nullif(checkout_previous_choices->v_worker_id::text,'null'::jsonb) end;
    checkout_legacy_labels:=case when checkout_choices is null then null
      when nullif(checkout_previous_choices->v_worker_id::text,'null'::jsonb) is null then checkout_previous_labels->>v_worker_id::text
      else checkout_previous_legacy_labels->>v_worker_id::text end;
    perform company_checkout_allowance_private.validate_labels(v_company_id,v_worker_id,v_worker->>'allowance_label',checkout_choices,checkout_legacy_labels);
    insert into public.daily_report_workers(''')
    source = regex_once(source, r'(      (?:allowance_amount,allowance_label,)?work_category)\n    \)', r'\1,company_allowance_selections,company_allowance_legacy_labels\n    )')
    source = regex_once(source, r"(      nullif\(v_worker\s*->>\s*'work_category',\s*''\))\n    \)",
        r'\1,checkout_choices,checkout_legacy_labels\n    )')
    source = once(source,'  return v_report_id;', '''  if (checkout_had_choices or exists(select 1 from public.daily_report_workers where report_id=v_report_id and company_allowance_selections is not null))
    and checkout_previous_basis is distinct from company_checkout_allowance_private.report_basis(v_report_id) then
    update public.daily_reports set representative_signature_json=null,representative_signer_name=null,
      supervisor_signature_json=null,supervisor_signer_name=null where id=v_report_id;
  end if;
  return v_report_id;''')
    return source

def sign_patch(source):
    source = once(source, 'declare scope_before jsonb;', 'declare scope_before jsonb; checkout_receipts jsonb;')
    source = once(source, '  update public.daily_reports\n  set status=',
        '  checkout_receipts:=company_checkout_allowance_private.capture_report(p_report_id);\n\n  update public.daily_reports\n  set status=')
    source = once(source, 'source_report_id,created_by,updated_by', 'source_report_id,company_allowance_receipt_id,created_by,updated_by')
    source = once(source, 'p_report_id,v_user_id,v_user_id', 'p_report_id,(checkout_receipts->>v_detail.worker_id::text)::uuid,v_user_id,v_user_id')
    source = once(source, '          source_report_id=p_report_id,', '          source_report_id=p_report_id,\n          company_allowance_receipt_id=(checkout_receipts->>v_detail.worker_id::text)::uuid,')
    return source

def refresh_patch(source):
    return once(source, '      if allowance_index is not null then',
        '''      if allowance_index is not null and not company_checkout_allowance_private.covers_legacy(cid,wid,a.work_date,allowance_index) then''')

def legacy_patch(source):
    source=once(source,' select c.items into individual_items',""" publication_items:=(select coalesce(jsonb_agg(e),'[]'::jsonb) from jsonb_array_elements(publication_items) e
  where e->>'origin' is distinct from 'company_legacy' or not exists(
   select 1 from public.attendance_entries a join company_checkout_allowance_private.receipts r
    on r.id=a.company_allowance_receipt_id and r.company_id=a.company_id and r.worker_id=a.worker_id
     and r.report_id=a.source_report_id and r.work_date=a.work_date
   cross join lateral jsonb_array_elements(r.snapshot->'items') selected
   where a.company_id=cid and a.worker_id=wid and a.work_date between p_start and p_end
    and selected->>'origin'='company_legacy' and selected->>'id'=e->>'id'
    and (select count(*) from generate_series(1,3) legacy_slot where nullif(btrim(raw->>('allowance_name_'||legacy_slot)),'')=e->>'name')=1
    and exists(select 1 from generate_series(1,3) legacy_slot
     where nullif(btrim(raw->>('allowance_name_'||legacy_slot)),'')=e->>'name'
      and coalesce((raw->>('allowance_'||legacy_slot))::numeric,0) is distinct from (e->>'amount_yen')::numeric)));
 select c.items into individual_items""")
    source = once(source, "where a.company_id=cid and a.worker_id=wid and a.work_date between p_start and p_end and a.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date order by name loop",
        "where a.company_id=cid and a.worker_id=wid and a.work_date between p_start and p_end and a.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date and a.company_allowance_receipt_id is null order by name loop")
    return once(source, "and item->>'name'=any(coalesce(a.allowance_names,'{}'::text[]));",
        "and a.company_allowance_receipt_id is null and not company_checkout_allowance_private.covers_item(cid,wid,a.work_date,(item->>'id')::uuid) and item->>'name'=any(coalesce(a.allowance_names,'{}'::text[]));")

def published_copy(source):
    source = once(source, 'FUNCTION payroll_unit_private.resolve_company_common(', 'FUNCTION company_checkout_allowance_private.resolve_published(')
    return once(source, 'and ae.base_man_days>0;',
        "and ae.base_man_days>0 and ae.company_allowance_receipt_id is null and not company_checkout_allowance_private.covers_item(cid,wid,ae.work_date,(item->>'id')::uuid);")

def detail_patch(source):
    source = once(source, "  settings jsonb := '{}'::jsonb;", "  settings jsonb := '{}'::jsonb; checkout_common jsonb; allowance_settings jsonb;")
    source = once(source, '  where s.company_id=cid and s.worker_id=wid;', '''  where s.company_id=cid and s.worker_id=wid;
  checkout_common:=payroll_unit_private.resolve_company_common(cid,wid,start_day,end_day);
  allowance_settings:=case when jsonb_typeof(checkout_common->'effective_settings')='object'
    then checkout_common->'effective_settings' else settings end;''')
    # Only the named legacy allowance projection uses effective settings.
    for n in range(1,4):
        source=once(source,"settings->>'allowance_name_"+str(n)+"'","allowance_settings->>'allowance_name_"+str(n)+"'")
        source=once(source,"settings->>'allowance_"+str(n)+"'","allowance_settings->>'allowance_"+str(n)+"'")
    source=once(source, '    group by a.allowance_name', '''      and not company_checkout_allowance_private.covers_legacy(cid,wid,ae.work_date,
        case when nullif(trim(settings->>'allowance_name_1'),'')=a.allowance_name then 1
             when nullif(trim(settings->>'allowance_name_2'),'')=a.allowance_name then 2
             when nullif(trim(settings->>'allowance_name_3'),'')=a.allowance_name then 3 else 0 end)
    group by a.allowance_name''')
    source=once(source, '      - v_allowance_total,', '''      - v_allowance_total
      - coalesce((select (ps.detail->>'custom_earnings_total')::numeric from public.payroll_statements ps
        where ps.company_id=cid and ps.worker_id=wid and ps.period_start=start_day and ps.period_end=end_day
          and ps.automatic_calculation and ps.workflow_state='draft' limit 1),0),''')
    return source

def augment_patch(source):
    return once(source," if common_items->'legacy_resolution' is not null then",''' resolved:=resolved||jsonb_build_object('company_checkout_resolution',common_items->'checkout_resolution');
 if common_items->'legacy_resolution' is not null then''')

WRAPPER = '''CREATE OR REPLACE FUNCTION payroll_unit_private.resolve_company_common(cid uuid, wid uuid, p_start date, p_end date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $checkout_wrapper$
declare prior jsonb;selected jsonb;rows jsonb;item jsonb;
begin
 prior:=company_checkout_allowance_private.resolve_published(cid,wid,p_start,p_end);
 selected:=company_checkout_allowance_private.resolve(cid,wid,p_start,p_end);
 rows:='[]';
 for item in select value from jsonb_array_elements(selected->'items') loop
  rows:=rows||jsonb_build_array(item||jsonb_build_object('source_origin',item->'origin','origin','company_common','inherited',true));
 end loop;
 return prior||jsonb_build_object('items',(prior->'items')||rows,
   'earnings',(prior->'earnings')||(selected->'earnings'),'deductions',(prior->'deductions')||(selected->'deductions'),
   'blocked',(prior->>'blocked')::boolean or (selected->>'blocked')::boolean,
   'checkout_resolution',selected);
end $checkout_wrapper$;
'''

def prepare():
    original=json.loads(FIXTURE.read_text())['functions']
    sources={fq(x['signature']):x for x in original}
    for x in original:
        if hashlib.md5(body(x['definition']).encode()).hexdigest()!=x['source_md5']: raise ValueError('Observed source checksum mismatch: '+x['signature'])
    patches={}
    for name in ['public.save_daily_report_draft(uuid,uuid,date,text,jsonb)','public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)']:
        patches[name]=draft_patch(sources[name]['definition'])
    patches['public.sign_daily_report(uuid,text,jsonb)']=sign_patch(sources['public.sign_daily_report(uuid,text,jsonb)']['definition'])
    patches['private.refresh_automatic_payroll_internal(uuid,uuid,date)']=refresh_patch(sources['private.refresh_automatic_payroll_internal(uuid,uuid,date)']['definition'])
    patches['company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date)']=legacy_patch(sources['company_common_canonical_review_private.resolve_legacy(uuid,uuid,date,date,jsonb,bigint,date)']['definition'])
    patches['private.sync_payroll_attendance_detail(uuid,uuid,date)']=detail_patch(sources['private.sync_payroll_attendance_detail(uuid,uuid,date)']['definition'])
    patches['payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)']=augment_patch(sources['payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)']['definition'])
    patches['payroll_unit_private.resolve_company_common(uuid,uuid,date,date)']=WRAPPER
    expected={name:sources[name]['source_md5'] for name in patches}
    sql="-- PRIVATE REVIEW UNIT. Not deployed; hour work-time source remains explicitly unavailable.\nbegin;set local lock_timeout='3s';set local statement_timeout='30s';\n"
    sql+="do $preflight$ begin if current_user<>'postgres' then raise exception 'reviewed owner required';end if;\n"
    sql+="if to_regnamespace('company_checkout_allowance_private') is not null then raise exception 'review schema already exists';end if;\n"
    for name,md5 in expected.items():
        sql+="if not exists(select 1 from pg_proc where oid=to_regprocedure("+literal(name)+") and md5(prosrc)="+literal(md5)+" and proowner='postgres'::regrole) then raise exception 'source boundary differs: "+name+"';end if;\n"
    sql+="end $preflight$;\n"
    names=','.join(literal(n)+'::regprocedure' for n in patches)
    sql+="create temporary table checkout_procedures_before on commit drop as select oid,to_jsonb(p)-'prosrc' attributes from pg_proc p where oid in("+names+");\n"
    sql+=(ROOT/'docs/candidates/company_checkout_receipt_core.sql.review-only').read_text()+'\n'
    sql+=(ROOT/'docs/candidates/company_checkout_receipt_capture.sql.review-only').read_text()+'\n'
    sql+=published_copy(sources['payroll_unit_private.resolve_company_common(uuid,uuid,date,date)']['definition']).rstrip(';\n')+';\n'
    sql+="revoke all on function company_checkout_allowance_private.resolve_published(uuid,uuid,date,date) from public,anon,authenticated,service_role;\n"
    for source in patches.values(): sql+=source.rstrip(';\n')+';\n'
    sql+="do $postflight$ begin if exists(select 1 from checkout_procedures_before b join pg_proc p using(oid) where b.attributes is distinct from to_jsonb(p)-'prosrc') then raise exception 'existing function attributes changed';end if;end $postflight$;\n"
    sql+="create function public.company_checkout_allowance_contract_version() returns integer language sql stable security invoker set search_path='' as $$select 1$$;\nrevoke all on function public.company_checkout_allowance_contract_version() from public,anon,service_role;grant execute on function public.company_checkout_allowance_contract_version() to authenticated;\ncommit;\n"
    return sql,{'before_source_md5':expected,'after_source_md5':{n:hashlib.md5(body(s).encode()).hexdigest() for n,s in patches.items()},'receipt_core_only_is_not_complete':True,'actual_work_hours_source_connected':False}

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);a=p.parse_args()
    sql,manifest=prepare();manifest['sql_sha256']=hashlib.sha256(sql.encode()).hexdigest()
    a.output.write_text(sql);a.manifest.write_text(json.dumps(manifest,indent=2)+'\n')
if __name__=='__main__': main()
