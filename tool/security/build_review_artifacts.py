"""Offline reviewed SQL generator. No database client, DSN, network or execution."""
import hashlib
import json
from pathlib import Path
import common_payroll_unused_undo as undo
import owner_payroll_common_rehearsal as common


def scalar(sql):
    return '('+sql.rstrip().removesuffix(';')+')'


def capture(side):
    if side not in ('before','after'):raise ValueError('checkpoint_side_invalid')
    business=common.BUSINESS_SQL.rsplit('SELECT md5(',1)[0]
    digest="(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(name,hash) ORDER BY name),'[]')::text) FROM common_data_fingerprints)"
    all_business=business.replace(common.SCOPES,undo.CATALOG_SCOPE)
    catalog=scalar(undo.CATALOG_SNAPSHOT_SQL)
    functions=scalar(undo.FUNCTIONS_SQL)
    hashes=undo.literal(json.dumps(common.EXPECTED,separators=(',',':')))+'::jsonb'
    return business+"\nINSERT INTO sko_common_install_checkpoints(side,checkpoint) SELECT '"+side+"',jsonb_build_object('schema',1,'source_hashes',"+hashes+",'catalog',"+catalog+",'functions',"+functions+",'business_hash',"+digest+");\nDROP TABLE common_data_fingerprints;\n"+all_business+"\nUPDATE sko_common_install_checkpoints SET all_application_rows_hash="+digest+" WHERE side='"+side+"';\nDROP TABLE common_data_fingerprints;"


GUARDS="""DO $fresh_checkpoints$ DECLARE b jsonb;a jsonb;k text;sig text;old_function jsonb;new_function jsonb; BEGIN
 SELECT checkpoint INTO STRICT b FROM sko_common_install_checkpoints WHERE side='before';
 SELECT checkpoint INTO STRICT a FROM sko_common_install_checkpoints WHERE side='after';
 IF b->>'business_hash' IS DISTINCT FROM a->>'business_hash'
 OR (SELECT all_application_rows_hash FROM sko_common_install_checkpoints WHERE side='before') IS DISTINCT FROM (SELECT all_application_rows_hash FROM sko_common_install_checkpoints WHERE side='after')
 THEN RAISE EXCEPTION 'existing application rows changed'; END IF;
 FOREACH k IN ARRAY ARRAY['schemas','relations','attributes','policies','constraints','indexes','defaults','types','enums','rules','default_acls','event_triggers','roles'] LOOP
 IF NOT ((a->'catalog'->'catalog'->k) @> (b->'catalog'->'catalog'->k)) THEN RAISE EXCEPTION 'existing catalog changed: %',k; END IF;
 END LOOP;
 FOREACH sig IN ARRAY ARRAY['public.my_attendance_allowance_units()','payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)','payroll_unit_private.read_conditions(uuid,uuid,date)'] LOOP
 SELECT f-'definition' INTO STRICT old_function FROM jsonb_array_elements(b->'functions') f WHERE replace(f->>'signature',', ',',')=sig;
 SELECT f-'definition' INTO STRICT new_function FROM jsonb_array_elements(a->'functions') f WHERE replace(f->>'signature',', ',',')=sig;
 IF old_function IS DISTINCT FROM new_function THEN RAISE EXCEPTION 'original function identity/security changed'; END IF;
 END LOOP;
 IF (a->'catalog'->'catalog'->'database') IS DISTINCT FROM (b->'catalog'->'catalog'->'database') THEN RAISE EXCEPTION 'database ownership/ACL changed'; END IF;
END $fresh_checkpoints$;"""


def build(bundle):
    original=common.build_install(bundle)
    if not original.startswith('BEGIN;\n') or not original.endswith('\nROLLBACK;'):raise RuntimeError('install_shape_changed')
    # Private before/after are captured inside this SAME transaction and database.
    parts=['-- REVIEW ONLY. No deployment runner is provided. Keep all output private.',
        'BEGIN;',"SET LOCAL lock_timeout='3s';SET LOCAL statement_timeout='120s';",
        'LOCK TABLE public.company_rate_settings IN SHARE ROW EXCLUSIVE MODE;',
        'CREATE TEMP TABLE sko_common_install_checkpoints(side text PRIMARY KEY,checkpoint jsonb NOT NULL,all_application_rows_hash text) ON COMMIT PRESERVE ROWS;',
        capture('before'),original.removeprefix('BEGIN;\n').removesuffix('\nROLLBACK;')]
    parts.append('DO $all_unused$ BEGIN\n'+'\n'.join(' IF EXISTS(SELECT 1 FROM '+table+") THEN RAISE EXCEPTION 'new common table is not empty'; END IF;" for table in undo.NEW_TABLES)+'\nEND $all_unused$;')
    parts.extend([capture('after'),GUARDS,'COMMIT;',
        "-- Run only with operator-managed private output redirection. This SELECT is private evidence, not a safe chat result.",
        "SELECT jsonb_build_object('schema',1,'source_hashes',"+undo.literal(json.dumps(common.EXPECTED,separators=(',',':')))+"::jsonb,'before',(SELECT checkpoint FROM sko_common_install_checkpoints WHERE side='before'),'after',(SELECT checkpoint FROM sko_common_install_checkpoints WHERE side='after'),'all_application_rows_hash',(SELECT all_application_rows_hash FROM sko_common_install_checkpoints WHERE side='after'));",
        'DROP TABLE sko_common_install_checkpoints;'])
    return '\n'.join(parts)+'\n'


def main():
    root=Path(__file__).parent
    bundle=json.loads((root/'common_payroll_sources.json').read_text())
    sql=build(bundle)
    path=root/'company_common_default_off_install.sql.review-only'
    path.write_text(sql)
    (root/'fresh_checkpoint_capture.sql.review-only').write_text('-- REVIEW ONLY. Same capture used in install; output must be private.\nBEGIN;\nCREATE TEMP TABLE sko_common_install_checkpoints(side text PRIMARY KEY,checkpoint jsonb NOT NULL,all_application_rows_hash text);\n'+capture('before')+"\nSELECT checkpoint FROM sko_common_install_checkpoints WHERE side='before';\nROLLBACK;\n")
    (root/'postflight.sql.review-only').write_text('-- REVIEW ONLY. Read/check only; requires the exact four-source install.\n'+common.POSTFLIGHT+'\nDO $all_unused$ BEGIN\n'+'\n'.join('IF EXISTS(SELECT 1 FROM '+t+") THEN RAISE EXCEPTION 'common data was used'; END IF;" for t in undo.NEW_TABLES)+'\nEND $all_unused$;\n')

if __name__=='__main__':main()
