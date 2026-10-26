"""Offline exact-source patch assembler. Never connects to a database."""
from pathlib import Path
import hashlib,json,re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
def extract(path,name):
    text=path.read_text()
    match=re.search(r'(create(?: or replace)? function\s+'+re.escape(name)+r'\([\s\S]*?\bas\s+(\$\w*\$))([\s\S]*?)\2\s*;',text,re.I)
    if not match: raise ValueError(name)
    return match.group(0)
def body(definition):
    return re.search(r'\bas\s+(\$\w*\$)([\s\S]*)\1\s*;?\s*$',definition,re.I).group(2)
def once(text,old,new):
    if text.count(old)!=1: raise ValueError('Anchor count '+str(text.count(old))+': '+old[:90])
    return text.replace(old,new)
def literal(text): return "'"+text.replace("'","''")+"'"
originals={row['signature']:row['definition'] for row in json.loads((HERE/'source-originals.json').read_text())}
patches={}
for sig,source in originals.items():
    source=re.sub(r'(?i)^create function','create or replace function',source)
    if '.read_context(' in sig or '.resolve_own(' in sig:
        source=once(source,'||shared_daily_report_private.safe_signature_scope(r.id);','||shared_daily_report_private.safe_signature_scope(r.id)||explicit_report_finalization_private.context_metadata(r.id);')
    elif '.guard_report(' in sig:
        anchor=" if tg_op='UPDATE' and attendance_admin_override_private.permit_report(to_jsonb(old),to_jsonb(new)) then return new;end if;"
        source=once(source,anchor,anchor+"\n if tg_op='UPDATE' and explicit_report_finalization_private.edit_permitted(to_jsonb(old),to_jsonb(new)) then return new;end if;\n if tg_op='UPDATE' and explicit_report_finalization_private.required(old.id) and old.status<>'signed' and new.status='signed' and not explicit_report_finalization_private.permitted(old.id,'finalize') then raise sqlstate '55000' using message='explicit_report_finalization_required';end if;")
    elif '.collect_supervisor(' in sig or '.manage_signature(' in sig:
        target='rid' if sig.startswith('shared_report_edit_private') else 'r.id'
        match=re.search(r"execute 'select checkout_shared_hours_private.prepare_supervisor\(\$1,\$2\)' using [^;]+;",source)
        source=once(source,match.group(0),"if not explicit_report_finalization_private.required("+target+") then "+match.group(0)+' end if;')
    elif sig.startswith('private.save_daily_report_signature'):
        source=once(source,"  if r.status <> 'draft' then", "  perform explicit_report_finalization_private.enroll(r.id);\n  if explicit_report_finalization_private.required(r.id) then\n    if shared_daily_report_private.document_mode(r.id) then raise sqlstate '55000' using message='explicit_report_actual_revision_required';end if;\n    if p_role='representative' then perform explicit_report_finalization_private.auto_confirm(r.id);\n    elsif p_role='supervisor' then perform explicit_report_finalization_private.assert_supervisor(r.id);end if;\n  end if;\n  if r.status <> 'draft' then")
        source=once(source,'and not shared_daily_report_private.document_mode(r.id) then','and not shared_daily_report_private.document_mode(r.id) and not explicit_report_finalization_private.required(r.id) then')
    elif '.submit_report(' in sig:
        source=once(source,' perform shared_daily_report_private.enroll_work_report(rid);',' perform shared_daily_report_private.enroll_work_report(rid);\n perform explicit_report_finalization_private.enroll(rid);\n perform explicit_report_finalization_private.auto_confirm(rid,p_workers);')
    elif '.materialize_confirmed_worker(' in sig:
        source=once(source,' update public.daily_report_workers set overtime_hours='," if explicit_report_finalization_private.permitted(rid,'finalize') and after_row=to_jsonb(w) and explicit_report_finalization_private.facts_match(rid,wid,facts) then return;end if;\n update public.daily_report_workers set overtime_hours=")
    elif '.confirm_facts(' in sig:
        source=once(source,' facts:=shared_worker_facts_private.normalize_worker_facts(rid,wid,p_facts);'," facts:=shared_worker_facts_private.normalize_worker_facts(rid,wid,p_facts);\n if explicit_report_finalization_private.required(rid) and (r.representative_signature_json is not null or r.supervisor_signature_json is not null) and explicit_report_finalization_private.facts_match(rid,wid,facts) is distinct from true then raise sqlstate '55000' using message='explicit_report_edit_before_facts_change';end if;")
    elif sig.startswith('public.save_daily_report_destination_draft'):
        source=once(source,'  v_worker_id uuid;','  v_worker_id uuid;\n  explicit_previous_categories jsonb;')
        source=once(source,'  delete from public.daily_report_workers where report_id=v_report_id;',"  select coalesce(jsonb_object_agg(worker_id::text,work_category),'{}'::jsonb) into explicit_previous_categories from public.daily_report_workers where report_id=v_report_id;\n  delete from public.daily_report_workers where report_id=v_report_id;")
        source=once(source,"      nullif(v_worker->>'work_category',''),checkout_choices,checkout_legacy_labels", "      coalesce(nullif(v_worker->>'work_category',''),explicit_previous_categories->>v_worker_id::text),checkout_choices,checkout_legacy_labels")
    patches[sig]=source
pins=[{'signature':sig,'body_md5':hashlib.md5(body(source).encode()).hexdigest()} for sig,source in originals.items()]
feature=next(x for x in json.loads((HERE/'financial-source-originals.json').read_text()) if x['identity']=='private.has_company_feature(uuid,text)')
pins.append({'signature':'private.has_company_feature(uuid,text)','body_md5':feature['body_md5']})
checks='\n'.join(" if not exists(select 1 from pg_proc p where p.oid=to_regprocedure("+literal(x['signature'])+") and md5(p.prosrc)="+literal(x['body_md5'])+" and pg_get_userbyid(p.proowner)='postgres') then raise exception 'explicit_finalization_source_changed: "+x['signature']+"';end if;" for x in pins)
core=(HERE/'core.sql').read_text()
sql='-- REVIEW ONLY. Default OFF. No production activation or employee data mutation.\nbegin;\ndo $pins$ begin\n'+checks+'\nend $pins$;\n'+core+'\n'+'\n'.join(patches.values())+'\ncommit;\n'
(HERE/'explicit-finalization.sql.review-only').write_text(sql)
(HERE/'source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')
(HERE/'source-originals.json').write_text(json.dumps([{'signature':k,'body_md5':hashlib.md5(body(v).encode()).hexdigest(),'definition':v} for k,v in originals.items()],ensure_ascii=False,separators=(',',':'))+'\n')
print(json.dumps({'functions':len(originals),'sql_sha256':hashlib.sha256(sql.encode()).hexdigest()}))
