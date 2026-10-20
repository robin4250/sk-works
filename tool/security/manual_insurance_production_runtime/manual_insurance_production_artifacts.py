"""Offline SQL builder. Never connects, saves premiums, refreshes payroll or undoes automatically."""
import hashlib
import json
import os
from pathlib import Path
import re
import owner_manual_insurance_install_rehearsal as native

SIGNATURES={
 'payroll_tax_private.validate_conditions(jsonb)':'4da2bc7e0e19291fba7a5a588e143315',
 'payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)':'17ab2de831a2db457b8ad7ae4283b7fc',
 'payroll_tax_private.read_conditions(uuid,uuid)':'bf7cb912a973c4ca71fea8cd259c2190',
 'private.apply_payroll_custom_money()':'5a2ee941d0ab23e56f588e4218103670'}

def literal(value):return "'"+str(value).replace("'","''")+"'"
def fail(test,code):
 if not test:raise RuntimeError(code)

def signatures_sql():return 'ARRAY['+','.join(literal(s)+'::regprocedure' for s in SIGNATURES)+']'

# Any retained use, including a later reverted profile, prevents code-only undo.
USED_SQL="""(EXISTS(SELECT 1 FROM payroll_tax_private.worker_conditions WHERE value->>'insurance_mode'='manual')
 OR EXISTS(SELECT 1 FROM payroll_tax_private.condition_history WHERE before_value->>'insurance_mode'='manual' OR after_value->>'insurance_mode'='manual')
 OR EXISTS(SELECT 1 FROM public.payroll_statements WHERE jsonb_path_exists(detail,'$.** ? (@.insurance_mode == "manual")'))
 OR EXISTS(SELECT 1 FROM payroll_final_private.history WHERE jsonb_path_exists(value,'$.** ? (@.insurance_mode == "manual")')))""".replace('\n',' ')
DB_META_SQL="SELECT md5(to_jsonb(d)::text) FROM pg_database d WHERE datname=current_database()"
FUNCTIONS_SQL="SELECT coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'body_hash',md5(p.prosrc),'metadata',to_jsonb(p)-'prosrc'-'prosqlbody') ORDER BY p.oid::regprocedure::text),'[]') FROM pg_proc p WHERE p.oid=ANY("+signatures_sql()+")"
CHECKPOINT_SQL="SELECT jsonb_build_object('schema',1,'functions',("+FUNCTIONS_SQL+"),'business_hash',pg_temp.manual_install_business_hash(),'table_hash',("+native.TABLE_SQL+"),'other_bodies_hash',("+native.UNCHANGED_BODY_SQL+"),'database_hash',("+DB_META_SQL+"),'manual_used',"+USED_SQL+")"
INIT_SQL="CREATE TEMP TABLE IF NOT EXISTS manual_install_runtime_probe(value boolean) ON COMMIT PRESERVE ROWS;\n"+native.FINGERPRINT_SQL.replace('CREATE FUNCTION pg_temp.','CREATE OR REPLACE FUNCTION pg_temp.')

EXTERNAL_BEFORE_SQL="DO $external_before$ BEGIN PERFORM set_config('sko.manual_install.external_before',("+CHECKPOINT_SQL+")::text,false);END $external_before$;"

LOCK_TABLES_SQL="DO $lock_rows$ DECLARE r record;BEGIN FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN "+native.SCHEMAS+" AND c.relkind IN ('r','p') ORDER BY n.nspname,c.relname LOOP EXECUTE format('LOCK TABLE %I.%I IN SHARE MODE',r.nspname,r.relname);END LOOP;END $lock_rows$;"

def build_install(directory):
 sql=native.build_install_rollback(directory)
 sql=sql.removesuffix('ROLLBACK;')
 # The temp scanner is already created by the single-session driver.
 sql=sql.replace('CREATE TEMP TABLE manual_install_runtime_probe(value boolean) ON COMMIT DROP;\n'+native.FINGERPRINT_SQL+'\n','',1)
 guard="DO $unused_install$ BEGIN IF "+USED_SQL+" THEN RAISE EXCEPTION 'manual mode already used: install refused';END IF;END $unused_install$;"
 sql=sql.replace('BEGIN;','BEGIN;\n'+LOCK_TABLES_SQL+"\nDO $external_before_guard$ BEGIN IF nullif(current_setting('sko.manual_install.external_before',true),'') IS NULL OR ("+CHECKPOINT_SQL+") IS DISTINCT FROM current_setting('sko.manual_install.external_before')::jsonb THEN RAISE EXCEPTION 'external before checkpoint changed: install refused';END IF;END $external_before_guard$;\n"+guard+"\nSELECT set_config('sko.manual_install.before',("+CHECKPOINT_SQL+"::text),true);",1)
 sql='\n'.join('DO $runtime_capture$ BEGIN PERFORM '+line.removeprefix('SELECT ')+' END $runtime_capture$;' if line.startswith('SELECT set_config(') else line for line in sql.splitlines())+'\n'
 return sql+"SELECT jsonb_build_object('schema',1,'before',current_setting('sko.manual_install.before')::jsonb,'after',("+CHECKPOINT_SQL+"));\nCOMMIT;\n"

def validate_proof(proof):
 fail(proof.get('schema')==1,'proof_schema_invalid')
 before=proof['before'];after=proof['after']
 for value in (before,after):
  fail(value.get('schema')==1 and value.get('manual_used') is False,'manual_mode_used')
  fail(len(value['functions'])==4,'function_count_invalid')
  fail({row['signature'] for row in value['functions']}==set(SIGNATURES),'function_set_invalid')
  for row in value['functions']:
   body=re.search(r'AS (\$\w*\$)(.*?)\1',row['definition'],re.S)
   fail(body is not None and hashlib.md5(body.group(2).encode()).hexdigest()==row['body_hash'],'definition_body_hash_invalid')
  for key in ('business_hash','table_hash','other_bodies_hash','database_hash'):fail(re.fullmatch(r'[a-f0-9]{32}',value.get(key,'')) is not None,'checkpoint_hash_invalid')
 for key in ('business_hash','table_hash','other_bodies_hash','database_hash'):fail(before[key]==after[key],'install_changed_existing_state')
 old={x['signature']:x for x in before['functions']};new={x['signature']:x for x in after['functions']}
 for signature in SIGNATURES:
  fail(old[signature]['body_hash']==SIGNATURES[signature],'before_body_hash_invalid')
  fail(old[signature]['metadata']==new[signature]['metadata'],'function_metadata_changed')
  fail(old[signature]['body_hash']!=new[signature]['body_hash'],'function_not_patched')
 return before,after

def build_unused_undo(proof):
 before,after=validate_proof(proof)
 expected=literal(json.dumps(after,separators=(',',':')))+'::jsonb'
 # Canonical JSON equality includes exact installed bodies, owners, OIDs, ACLs,
 # every table fingerprint and retained use. Unknown state never permits undo.
 sql="BEGIN;\nSET LOCAL lock_timeout='3s';SET LOCAL statement_timeout='60s';\n"+INIT_SQL+'\n'+LOCK_TABLES_SQL+'\n'+"DO $undo_guard$ DECLARE actual jsonb;BEGIN SELECT ("+CHECKPOINT_SQL+") INTO actual;IF "+USED_SQL+" OR actual IS DISTINCT FROM "+expected+" THEN RAISE EXCEPTION 'manual contract used or state changed: code-only undo refused';END IF;END $undo_guard$;\n"
 for row in before['functions']:
  fail(row['definition'].startswith('CREATE OR REPLACE FUNCTION '),'definition_invalid')
  sql+=row['definition']+';\n'
 sql+="DO $undo_post$ DECLARE actual jsonb;BEGIN SELECT ("+CHECKPOINT_SQL+") INTO actual;IF actual IS DISTINCT FROM "+literal(json.dumps(before,separators=(',',':')))+"::jsonb THEN RAISE EXCEPTION 'manual undo checkpoint differs';END IF;END $undo_post$;\nCOMMIT;\n"
 return sql

def generate(source,target):
 source=Path(source);target=Path(target)
 for path in (source,target.parent):fail(not any(p.is_symlink() for p in (path,*path.parents)),'private_path_required')
 fail(source.is_file() and not source.stat().st_mode&0o077 and source.stat().st_size<16777216,'private_checkpoint_required')
 fail(target.parent.is_dir() and not target.parent.stat().st_mode&0o077,'private_output_required')
 sql=build_unused_undo(json.loads(source.read_text()))
 fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'w') as handle:handle.write(sql)
