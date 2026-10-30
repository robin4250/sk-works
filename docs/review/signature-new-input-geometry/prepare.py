from pathlib import Path
import json,re,hashlib
root=Path(__file__).resolve().parent
sources=json.loads((root/'source-fixtures.json').read_text())
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
body=lambda s:re.search(r'AS \$function\$(.*?)\$function\$',s,re.S).group(1)
fragments=[];pins=[]
for f in sources['writers']:
 definition=f['definition'];assert hashlib.md5(body(definition).encode()).hexdigest()==f['source_md5']
 if f['schema']=='private' and f['proname']=='save_daily_report_signature':
  marker="  if shared_daily_report_private.document_mode(r.id) then\n    update shared_daily_report_private.work_protocol"
  replacement="  perform signature_new_input_private.require_ink(p_signature_json);\n"+marker
 elif f['schema']=='private':
  marker=" if p_role='reporter' and r.representative_signature_json is null then"
  replacement=" perform signature_new_input_private.require_ink(p_signature_json);\n"+marker
 else:
  marker="  checkout_receipts:=company_checkout_allowance_private.capture_report(p_report_id);"
  replacement="  perform signature_new_input_private.require_financial_signature(p_signature_json);\n"+marker
 assert definition.count(marker)==1
 changed=definition.replace(marker,replacement);fragments.append(changed+';\n')
 pins.append({'schema':f['schema'],'name':f['proname'],'identity':f['identity'],'before':f['source_md5'],'after':hashlib.md5(body(changed).encode()).hexdigest()})
core=(root/'validator-core.sql').read_text()
head="-- REVIEW ONLY. Source-pinned new signature input validation. No production authorization.\nbegin;set local lock_timeout='3s';set local statement_timeout='30s';\ndo $pre$ begin\n if current_user<>'postgres' or to_regnamespace('signature_new_input_private') is not null then raise exception 'new_signature_input_install_unavailable';end if;\n"
for pin in pins:
 head+=" if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='"+pin['schema']+"' and p.proname='"+pin['name']+"' and pg_get_function_identity_arguments(p.oid)='"+pin['identity']+"' and md5(p.prosrc)='"+pin['before']+"') then raise exception 'new_signature_input_original_source_changed';end if;\n"
head+=" if (select md5(prosrc) from pg_proc where oid='checkout_report_registration_private.has_signature(text,jsonb)'::regprocedure) is distinct from '"+sources['historical_interpreter']['source_md5']+"' then raise exception 'new_signature_input_history_source_changed';end if;\nend $pre$;\n"
head+="create temporary table new_signature_original_attributes on commit drop as select p.oid,(to_jsonb(p)-'prosrc') attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where "+' or '.join("(n.nspname='"+p['schema']+"' and p.proname='"+p['name']+"' and pg_get_function_identity_arguments(p.oid)='"+p['identity']+"')"for p in pins)+";\n"
post="do $post$ begin\n if not exists(select 1 from pg_namespace n where n.nspname='signature_new_input_private' and pg_get_userbyid(n.nspowner)='postgres' and n.nspacl is not distinct from ARRAY['postgres=UC/postgres']::aclitem[]) then raise exception 'new_signature_input_schema_attributes_changed';end if;\n if exists(select 1 from new_signature_original_attributes o left join pg_proc p on p.oid=o.oid where p.oid is null or (to_jsonb(p)-'prosrc') is distinct from o.attributes) then raise exception 'new_signature_input_existing_attributes_changed';end if;\n"
for pin in pins:
 post+=" if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='"+pin['schema']+"' and p.proname='"+pin['name']+"' and pg_get_function_identity_arguments(p.oid)='"+pin['identity']+"' and md5(p.prosrc)='"+pin['after']+"') then raise exception 'new_signature_input_updated_body_differ';end if;\n"
post+=" if (select md5(prosrc) from pg_proc where oid='checkout_report_registration_private.has_signature(text,jsonb)'::regprocedure) is distinct from '"+sources['historical_interpreter']['source_md5']+"' then raise exception 'new_signature_input_history_source_changed';end if;\n"
for name in ['require_ink','require_financial_signature']:
 match=re.search(r'create function signature_new_input_private\.'+name+r'\(.*?as \$\$(.*?)\$\$;',core,re.S);assert match
 md5=hashlib.md5(match.group(1).encode()).hexdigest()
 post+=" if not exists(select 1 from pg_proc p where p.oid='signature_new_input_private."+name+"(jsonb)'::regprocedure and md5(p.prosrc)='"+md5+"' and pg_get_userbyid(p.proowner)='postgres' and not p.prosecdef and p.provolatile='i' and not p.proisstrict and p.proparallel='u' and not p.proleakproof and p.proconfig=ARRAY['search_path=\"\"']::text[] and p.proacl is not distinct from ARRAY['postgres=X/postgres']::aclitem[]) then raise exception 'new_signature_input_helper_attributes_changed';end if;\n"
post+='end $post$;\ncommit;\n'
(root/'install.sql.review-only').write_text(head+core+'\n'+''.join(fragments)+post)
(root/'source-pins.json').write_text(json.dumps({'writers':pins,'historical_has_signature_unchanged':sources['historical_interpreter']['source_md5'],'validator_sha256':sha(core),'candidate_sha256':sha(head+core+'\n'+''.join(fragments)+post)},indent=2)+'\n')
