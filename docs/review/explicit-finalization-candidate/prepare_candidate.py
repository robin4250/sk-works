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
original_rows=json.loads((HERE/'source-originals.json').read_text())
originals={row['signature']:row['definition'] for row in original_rows}
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
pins=[{k:v for k,v in row.items() if k!='definition'} for row in original_rows]
feature=next(x for x in json.loads((HERE/'financial-source-originals.json').read_text()) if x['identity']=='private.has_company_feature(uuid,text)')
pins.append({'signature':'private.has_company_feature(uuid,text)',**{k:v for k,v in feature.items() if k not in ('identity','definition')}})
def meta_guard(x):
    conditions=["p.oid=to_regprocedure("+literal(x['signature'])+")","md5(p.prosrc)="+literal(x['body_md5']),"pg_get_userbyid(p.proowner)="+literal(x.get('owner','postgres'))]
    if 'security_definer' in x: conditions.append("p.prosecdef="+str(x['security_definer']).lower())
    if 'volatility' in x: conditions.append("p.provolatile="+literal(x['volatility']))
    if 'config' in x: conditions.append("p.proconfig is not distinct from "+("array["+','.join(literal(v) for v in x['config'])+"]::text[]" if x['config'] is not None else 'null::text[]'))
    if 'acl' in x: conditions.append("p.proacl is not distinct from "+(literal(x['acl'])+'::aclitem[]' if x['acl'] is not None else 'null::aclitem[]'))
    return " if not exists(select 1 from pg_proc p where "+' and '.join(conditions)+") then raise exception 'explicit_finalization_source_changed: "+x['signature']+"';end if;"
checks='\n'.join(meta_guard(x) for x in pins)
core=(HERE/'core.sql').read_text()
sql='-- REVIEW ONLY. Default OFF. No production activation or employee data mutation.\nbegin;\nset local lock_timeout=\'5s\';set local statement_timeout=\'45s\';\ndo $install$ begin if current_user<>\'postgres\' or to_regnamespace(\'explicit_report_finalization_private\') is not null then raise exception \'explicit_finalization_install_precondition\';end if;end $install$;\ndo $pins$ begin\n'+checks+'\nend $pins$;\n'+core+'\n'+'\n'.join(x.rstrip().rstrip(';')+';' for x in patches.values())+'\ncommit;\n'
(HERE/'explicit-finalization.sql.review-only').write_text(sql)
(HERE/'source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')
# source-originals.json remains the exact readonly production catalog, including ACL/owner/config.
print(json.dumps({'functions':len(originals),'sql_sha256':hashlib.sha256(sql.encode()).hexdigest()}))

# Independent route-visit document contract; no normal financial schema dependency.
route_originals=json.loads((HERE/'route-source-originals.json').read_text())
route_patches=[]
for row in route_originals:
    source=re.sub(r'(?i)^create function','create or replace function',row['definition'])
    if 'list_saved_route_visit_reports(' in row['signature']:
        source=once(source,'r.created_by = auth.uid()',"(case when explicit_route_finalization_private.required(r.id) then explicit_route_finalization_private.actor_allowed(r.id) else r.created_by=auth.uid() end)")
        route_patches.append(source)
        continue
    source=once(source,'r.created_by<>auth.uid()',"(case when explicit_route_finalization_private.required(r.id) then not explicit_route_finalization_private.actor_allowed(r.id) else r.created_by<>auth.uid() end)")
    if '.route_visit_report_command(' in row['signature']:
        source=once(source,'  if r.created_by', '  if r.created_by') if '  if r.created_by' in source else source
        source=once(source," if p_command='draft' and r.status='draft' then", " if explicit_route_finalization_private.required(r.id) then perform explicit_route_finalization_private.lock_actor(r.id);end if;\n if p_command='draft' and r.status='draft' then")
        source=once(source," if p_command='read' then return c; end if;", " if p_command='read' then return explicit_route_finalization_private.decorate(c); end if;")
    else:
        source=once(source," if p_role not in ('reporter','responsible')", " if explicit_route_finalization_private.required(r.id) then\n  perform explicit_route_finalization_private.lock_actor(r.id);perform explicit_route_finalization_private.enroll(r.id);\n  if (case when p_role='reporter' then r.representative_signature_json else r.supervisor_signature_json end) is not null then\n   if (case when p_role='reporter' then r.representative_signature_json else r.supervisor_signature_json end) is distinct from p_signature_json or (case when p_role='reporter' then r.representative_signer_name else r.supervisor_signer_name end) is distinct from trim(p_signer_name) then raise sqlstate '55000' using message='explicit_route_signature_already_saved';end if;\n   return explicit_route_finalization_private.decorate(to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name)));\n  end if;\n end if;\n if p_role not in ('reporter','responsible')")
        source=once(source,"status='completed',signed_at=now(),", "status=case when explicit_route_finalization_private.required(r.id) then 'reporter_signed' else 'completed' end,signed_at=case when explicit_route_finalization_private.required(r.id) then null else now() end,")
        source=once(source,"then return to_jsonb(r); end if;", "then return explicit_route_finalization_private.decorate(to_jsonb(r)); end if;")
    source=once(source," return to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name));", " return explicit_route_finalization_private.decorate(to_jsonb(r)||jsonb_build_object('daily_report_workers',r.workers,'sites',jsonb_build_object('name',r.site_name)));")
    route_patches.append(source)
route_checks='\n'.join(meta_guard(x) for x in route_originals)
route_sql='-- REVIEW ONLY. Default OFF. Independent visit documents; no financial-row mutation.\nbegin;\nset local lock_timeout=\'5s\';set local statement_timeout=\'45s\';\ndo $install$ begin if current_user<>\'postgres\' or to_regnamespace(\'explicit_route_finalization_private\') is not null then raise exception \'explicit_route_install_precondition\';end if;end $install$;\ndo $pins$ begin\n'+route_checks+'\nend $pins$;\n'+(HERE/'route-core.sql').read_text()+'\n'+'\n'.join(x.rstrip().rstrip(';')+';' for x in route_patches)+'\ncommit;\n'
(HERE/'explicit-route-finalization.sql.review-only').write_text(route_sql)

# Unused OFF restoration only. Existing definitions/owner/config/ACL must match.
def restore(namespace,original_rows,patched_sources,new_functions,triggers):
    post=[]
    for row,source in zip(original_rows,patched_sources):
        post.append({**row,'body_md5':hashlib.md5(body(source).encode()).hexdigest()})
    sql="-- REVIEW ONLY. Refuses used/enabled modules. Exact post-source restoration.\nbegin;\nset local lock_timeout='5s';set local statement_timeout='45s';\ndo $unused$ begin\n if current_user<>'postgres' then raise exception 'unused_restore_postgres_required';end if;\n"
    tables=['states','events','receipts','permits']
    for table in tables:sql+=" if exists(select 1 from "+namespace+'.'+table+") then raise exception 'explicit_finalization_restore_used_module';end if;\n"
    for table in ['rollout','reports']:sql+=" if exists(select 1 from "+namespace+'.'+table+" where enabled) then raise exception 'explicit_finalization_restore_enabled_module';end if;\n"
    sql+='\n'.join(meta_guard(x) for x in post)+"\nend $unused$;\n"
    for row in reversed(original_rows):sql+=re.sub(r'(?i)^create function','create or replace function',row['definition'])+';\n'
    for function in reversed(new_functions):sql+='drop function '+function+';\n'
    for trigger,table in reversed(triggers):sql+='drop trigger '+trigger+' on '+table+';\n'
    return sql+'drop schema '+namespace+' cascade;\ncommit;\n'
(HERE/'explicit-finalization-restore-unused.sql.review-only').write_text(restore('explicit_report_finalization_private',original_rows,list(patches.values()),['public.start_shared_report_finalization_edit(uuid,timestamptz,text,text)','public.finalize_shared_daily_report(uuid,timestamptz,text)'],[('zzzz_explicit_report_receipts','public.daily_reports')]))
(HERE/'explicit-route-finalization-restore-unused.sql.review-only').write_text(restore('explicit_route_finalization_private',route_originals,route_patches,['public.start_route_visit_report_finalization_edit(uuid,timestamptz,text,text)','public.finalize_route_visit_report(uuid,timestamptz,text)'],[('zzzz_explicit_route_receipts','private.route_visit_reports'),('explicit_route_completion_gate','private.route_visit_reports')]))
