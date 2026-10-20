"""Exact four-artifact common-payroll undo, only immediately after unused install.

This generates operator-only SQL from captured private native DB checkpoints.
It is not a general DDL reverser, used-data rollback, or complete backup restore.
"""
import json
import re
import owner_payroll_common_rehearsal as common

NEW_SCHEMAS = ('company_allowance_identity_private','company_common_allowance_private')
NEW_TABLES = (
 'company_allowance_identity_private.state','company_allowance_identity_private.identities','company_allowance_identity_private.history',
 'company_common_allowance_private.state','company_common_allowance_private.items','company_common_allowance_private.history',
 'company_common_allowance_private.unit_aliases','company_common_allowance_private.requests','company_common_allowance_private.payroll_activation',
 'company_common_allowance_private.payroll_publications','company_common_allowance_private.payroll_publication_receipts',
)
REPLACED = (
 'public.my_attendance_allowance_units()',
 'payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)',
 'payroll_unit_private.read_conditions(uuid,uuid,date)',
)
NEW_TRIGGERS = (
 ('public.company_rate_settings','company_allowance_identity_track'),
 ('public.company_rate_settings','company_allowance_identity_no_delete'),
 ('public.company_rate_settings','company_allowance_identity_no_reinsert'),
 ('public.company_rate_settings','company_common_allowance_unit_compat'),
 ('company_common_allowance_private.payroll_publications','immutable_common_payroll_publication'),
 ('company_common_allowance_private.payroll_publication_receipts','immutable_common_payroll_receipt'),
)
# Exact function names declared by the pinned four sources, excluding replacements.
NEW_FUNCTION_NAMES = {
 'company_allowance_identity_private.slots','company_allowance_identity_private.authorize','company_allowance_identity_private.advance',
 'company_allowance_identity_private.current_value','company_allowance_identity_private.track_settings','company_allowance_identity_private.prevent_settings_delete',
 'company_allowance_identity_private.prevent_reinsert','company_allowance_identity_private.admin_state','company_allowance_identity_private.history_page',
 'company_allowance_identity_private.adopt','company_allowance_identity_private.labels','company_allowance_identity_private.edit_slot',
 'public.read_company_allowance_identity_history','public.read_company_allowance_identity_admin','public.adopt_company_allowance_identity',
 'public.read_company_allowance_identity_labels','public.save_company_allowance_identity_slot',
 'company_common_allowance_private.current_units','company_common_allowance_private.protect_unit_aliases','company_common_allowance_private.merge_unit_aliases',
 'company_common_allowance_private.session_id','company_common_allowance_private.authorize','company_common_allowance_private.lock_writer',
 'company_common_allowance_private.source','company_common_allowance_private.active_items','company_common_allowance_private.admin_state',
 'company_common_allowance_private.request_result','company_common_allowance_private.save','company_common_allowance_private.history_page','company_common_allowance_private.save_tax',
 'public.read_company_common_allowances_admin','public.save_company_common_allowances','public.read_company_common_allowance_request',
 'public.read_company_common_allowances_history','public.save_company_common_tax_settings',
 'payroll_unit_private.resolve_company_common','payroll_unit_private.common_state','payroll_unit_private.save_common_hours','public.save_payroll_common_hours',
 'company_common_allowance_private.protect_payroll_publication','company_common_allowance_private.read_payroll_publications',
 'company_common_allowance_private.publish_payroll','public.read_company_common_payroll_publications','public.publish_company_common_payroll',
}
CATALOG_SCOPE = r"n.nspname NOT LIKE 'pg\_%' ESCAPE '\' AND n.nspname<>'information_schema'"
_catalog = common.CATALOG_SQL.replace(common.SCOPES,CATALOG_SCOPE).removeprefix('SELECT md5(').removesuffix('::text);')
_extra = """,
 'constraints',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_constraint x JOIN pg_namespace n ON n.oid=x.connamespace WHERE SCOPE),
 'indexes',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.indexrelid),'[]') FROM pg_index x JOIN pg_class c ON c.oid=x.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'defaults',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_attrdef x JOIN pg_class c ON c.oid=x.adrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'types',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_type x JOIN pg_namespace n ON n.oid=x.typnamespace WHERE SCOPE),
 'enums',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_enum x JOIN pg_type t ON t.oid=x.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE SCOPE),
 'rules',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_rewrite x JOIN pg_class c ON c.oid=x.ev_class JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'comments',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.classoid,x.objoid,x.objsubid),'[]') FROM pg_description x),
 'security_labels',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.classoid,x.objoid,x.objsubid,x.provider),'[]') FROM pg_seclabel x),
 'default_acls',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_default_acl x),
 'dependencies',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.classid,x.objid,x.objsubid,x.refclassid,x.refobjid,x.refobjsubid,x.deptype),'[]') FROM pg_depend x WHERE
 (x.classid='pg_proc'::regclass AND x.objid IN(SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE SCOPE))
 OR (x.classid='pg_class'::regclass AND x.objid IN(SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE))
 OR (x.classid='pg_type'::regclass AND x.objid IN(SELECT t.oid FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE SCOPE))
 OR (x.classid='pg_constraint'::regclass AND x.objid IN(SELECT c.oid FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE SCOPE))
 OR (x.classid='pg_rewrite'::regclass AND x.objid IN(SELECT r.oid FROM pg_rewrite r JOIN pg_class c ON c.oid=r.ev_class JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE))
 OR (x.classid='pg_attrdef'::regclass AND x.objid IN(SELECT d.oid FROM pg_attrdef d JOIN pg_class c ON c.oid=d.adrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE))),
 'event_triggers',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_event_trigger x),
 'database',(SELECT jsonb_build_array(oid,datname,datdba,datacl,datallowconn) FROM pg_database WHERE datname=current_database()),
 'roles',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]') FROM pg_roles x)
""".replace('SCOPE',CATALOG_SCOPE)
CATALOG_EXPR = _catalog[:-1]+_extra+')'
CATALOG_HASH_SQL = 'SELECT md5(('+CATALOG_EXPR+')::text);'
CATALOG_SNAPSHOT_SQL = 'SELECT jsonb_build_object(\'hash\',md5(v::text),\'catalog\',v) FROM (SELECT '+CATALOG_EXPR+' v) checkpoint;'
FUNCTIONS_SQL = """SELECT coalesce(jsonb_agg(jsonb_build_object(
 'oid',p.oid,'name',n.nspname||'.'||p.proname,
 'signature',n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')',
 'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'owner_oid',p.proowner,'acl',p.proacl,'config',p.proconfig,'definer',p.prosecdef)
 ORDER BY p.oid),'[]') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (SCOPE) AND p.prokind='f';""".replace('SCOPE',CATALOG_SCOPE)

def literal(value):
    return "'"+value.replace("'","''")+"'"

def install_sql(bundle):
    sql=common.build_install(bundle)
    assert sql.endswith('ROLLBACK;')
    return sql.removesuffix('ROLLBACK;')+'COMMIT;'

def checkpoint(catalog,functions,business):
    if not re.fullmatch(r'[a-f0-9]{32}',catalog.get('hash','')) or not re.fullmatch(r'[a-f0-9]{32}',business):
        raise RuntimeError('invalid_checkpoint_hash')
    return {'schema':1,'source_hashes':common.EXPECTED,'catalog':catalog,'functions':functions,'business_hash':business}

def build_unused_undo(before,after):
    for x in (before,after):
        if x.get('schema')!=1 or x.get('source_hashes')!=common.EXPECTED:raise RuntimeError('checkpoint_source_mismatch')
        if not re.fullmatch(r'[a-f0-9]{32}',x['catalog']['hash']) or not re.fullmatch(r'[a-f0-9]{32}',x['business_hash']):raise RuntimeError('invalid_checkpoint_hash')
    if before['business_hash']!=after['business_hash']:raise RuntimeError('install_changed_business')
    originals={f['signature'].replace(', ',','):f for f in before['functions']}
    if any(x not in originals for x in REPLACED):raise RuntimeError('original_function_missing')
    prior_ids={f['oid'] for f in before['functions']}
    new=[f for f in after['functions'] if f['oid'] not in prior_ids]
    if {f['name'] for f in new}!=NEW_FUNCTION_NAMES or len(new)!=len(NEW_FUNCTION_NAMES):raise RuntimeError('exact_new_function_set_differs')
    # All original function OIDs and privileges must still exist. Only the three
    # pinned replacements are permitted to have changed definitions.
    current={f['oid']:f for f in after['functions']}
    for original in before['functions']:
        observed=current.get(original['oid'])
        if not observed:raise RuntimeError('existing_function_oid_lost')
        expected=dict(original)
        if original['signature'].replace(', ',',') in REPLACED:expected['definition']=observed['definition']
        if observed!=expected:raise RuntimeError('existing_function_metadata_changed')
    parts=['-- REVIEW ONLY: exact native checkpoint, unused immediate install only.','BEGIN;',"SET LOCAL statement_timeout='60s'; SET LOCAL lock_timeout='3s';",'LOCK TABLE public.company_rate_settings, '+', '.join(NEW_TABLES)+' IN ACCESS EXCLUSIVE MODE;']
    parts.append('DO $unused_guard$ BEGIN\n IF (SELECT md5(('+CATALOG_EXPR+')::text)) IS DISTINCT FROM '+literal(after['catalog']['hash'])+" THEN RAISE EXCEPTION 'installed catalog drift: undo refused'; END IF;\n")
    for table in NEW_TABLES:
        parts.append(' IF EXISTS(SELECT 1 FROM '+table+") THEN RAISE EXCEPTION 'common payroll was used: undo refused'; END IF;")
    parts.append('END $unused_guard$;')
    # Existing data must still match the captured original. This is intentionally
    # more restrictive than merely checking the new common tables.
    parts.append(common.BUSINESS_SQL.rsplit('SELECT md5(',1)[0])
    parts.append("DO $business_guard$ BEGIN IF (SELECT md5(coalesce(jsonb_agg(jsonb_build_array(name,hash) ORDER BY name),'[]')::text) FROM common_data_fingerprints) IS DISTINCT FROM "+literal(before['business_hash'])+" THEN RAISE EXCEPTION 'existing business changed: undo refused'; END IF; END $business_guard$; DROP TABLE common_data_fingerprints;")
    parts.extend(originals[x]['definition']+';' for x in REPLACED)
    parts.extend('DROP TRIGGER '+name+' ON '+table+' RESTRICT;' for table,name in NEW_TRIGGERS)
    new.sort(key=lambda f:(0 if f['name'].startswith('public.') else 1 if f['name'].startswith('payroll_unit_private.') else 2,f['name']))
    parts.append('DROP FUNCTION '+', '.join(f['signature'] for f in new)+' RESTRICT;')
    parts.append('DROP TABLE '+', '.join(NEW_TABLES)+' RESTRICT;')
    parts.extend('DROP SCHEMA '+schema+' RESTRICT;' for schema in NEW_SCHEMAS)
    parts.append('DO $restored$ BEGIN IF (SELECT md5(('+CATALOG_EXPR+')::text)) IS DISTINCT FROM '+literal(before['catalog']['hash'])+" THEN RAISE EXCEPTION 'original catalog mismatch: undo rolled back'; END IF; END $restored$;")
    parts.append('COMMIT;')
    return '\n'.join(parts)

def rejection_assertion(undo_sql,message):
    start=undo_sql.index('DO $unused_guard$')
    end=undo_sql.index('END $unused_guard$;',start)+len('END $unused_guard$;')
    guard=undo_sql[start:end]
    return "DO $rejection_test$ DECLARE rejected boolean:=false; BEGIN BEGIN EXECUTE "+literal(guard)+"; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM="+literal(message)+" THEN rejected:=true; ELSE RAISE; END IF; END; IF NOT rejected THEN RAISE EXCEPTION 'unused undo did not reject protected case'; END IF; END $rejection_test$;"
