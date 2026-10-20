#!/usr/bin/env python3
"""Install-only four-function compatibility check on a fresh offline archive clone."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid
import owner_expense_off_rehearsal as transport

SCHEMAS="('public','private','payroll_tax_private','payroll_unit_private','resident_tax_private','company_common_allowance_private','company_allowance_identity_private')"
CATALOG_SQL="SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]')::text) FROM (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN "+SCHEMAS+") x;"
UNCHANGED_BODY_SQL="SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.oid),'[]')::text) FROM (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN "+SCHEMAS+" AND p.oid<>ALL(ARRAY['payroll_tax_private.validate_conditions(jsonb)'::regprocedure,'payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)'::regprocedure,'payroll_tax_private.read_conditions(uuid,uuid)'::regprocedure,'private.apply_payroll_custom_money()'::regprocedure])) x"
METADATA_SQL="SELECT md5(coalesce(jsonb_agg(to_jsonb(x)-'prosrc'-'prosqlbody' ORDER BY x.oid),'[]')::text) FROM (SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN "+SCHEMAS+") x"
TABLE_SQL="SELECT md5(jsonb_build_object('classes',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.oid),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN "+SCHEMAS+" AND c.relkind IN ('r','p','S')),'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]') FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN "+SCHEMAS+"))::text)"
FINGERPRINT_SQL="""CREATE FUNCTION pg_temp.manual_install_business_hash() RETURNS text LANGUAGE plpgsql AS $fingerprint$
DECLARE r record; value text; items jsonb:='[]';
BEGIN
 FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN SCHEMA_LIST AND c.relkind='r' ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]'')::text) FROM %I.%I t',r.nspname,r.relname) INTO value;
  items:=items||jsonb_build_array(jsonb_build_array(r.nspname,r.relname,value));
 END LOOP;
 RETURN md5(items::text);
END $fingerprint$;""".replace('SCHEMA_LIST',SCHEMAS)

def check(value,code):
    if not value:raise RuntimeError(code)

def build_install_rollback(directory):
    manifest=json.loads((directory/'runtime_manifest.json').read_text())
    for name,expected in manifest['files'].items():
        path=directory/name
        check(path.parent==directory and path.is_file() and not path.is_symlink(),'runtime_file_invalid')
        check(hashlib.sha256(path.read_bytes()).hexdigest()==expected,'runtime_hash_mismatch')
    source=(directory/'payroll_manual_insurance_20261020.sql.review-only').read_text()
    source,count=re.subn(r'^BEGIN;\s*$','',source,count=1,flags=re.M)
    check(count==1 and source.rstrip().endswith('COMMIT;'),'outer_transaction_shape_changed')
    source=source.rstrip().removesuffix('COMMIT;')
    check(not re.search(r'^\s*(BEGIN|COMMIT|ROLLBACK|START TRANSACTION)\s*;',source,re.I|re.M),'nested_transaction_refused')
    return '\n'.join(['BEGIN;','CREATE TEMP TABLE manual_install_runtime_probe(value boolean) ON COMMIT DROP;',FINGERPRINT_SQL,
        "SELECT set_config('sko.manual_install.business',pg_temp.manual_install_business_hash(),true);",
        "SELECT set_config('sko.manual_install.other_bodies',("+UNCHANGED_BODY_SQL+"),true);",
        "SELECT set_config('sko.manual_install.metadata',("+METADATA_SQL+"),true);",
        "SELECT set_config('sko.manual_install.tables',("+TABLE_SQL+"),true);",source,
        "DO $postcheck$ BEGIN IF pg_temp.manual_install_business_hash() IS DISTINCT FROM current_setting('sko.manual_install.business') THEN RAISE EXCEPTION 'manual install changed existing business rows';END IF;",
        "IF ("+UNCHANGED_BODY_SQL+") IS DISTINCT FROM current_setting('sko.manual_install.other_bodies') THEN RAISE EXCEPTION 'manual install changed unrelated function bodies';END IF;",
        "IF ("+METADATA_SQL+") IS DISTINCT FROM current_setting('sko.manual_install.metadata') THEN RAISE EXCEPTION 'manual install changed function OID owner ACL or metadata';END IF;",
        "IF ("+TABLE_SQL+") IS DISTINCT FROM current_setting('sko.manual_install.tables') THEN RAISE EXCEPTION 'manual install changed existing tables policies or owners';END IF;",
        "IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='payroll_tax_private.read_conditions(uuid,uuid)'::regprocedure AND prosrc LIKE '%manual_insurance_contract_version%') THEN RAISE EXCEPTION 'manual reader capability absent';END IF;END $postcheck$;",
        'ROLLBACK;'])

def main():
    os.umask(0o077)
    stage=None;clone=None;created=False;code=1
    status={'schema':1,'verified':False,'production_connected':False,'owner_acl_changed':False,
        'insurance_amount_saved':False,'payroll_recalculated':False,'common_activation_written':False,'real_login_verified':False}
    try:
        check(sys.platform=='darwin','mac_required')
        check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        install=build_install_rollback(Path(__file__).parent)
        root=Path.home()/'SKO-source-backups';source=root/transport.SOURCE
        check(not any(p.is_symlink() for p in (source,*source.parents)) and not root.stat().st_mode&0o077,'private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        check(original.get('archive_restore_verified') and original.get('container_stopped'),'verified_stopped_source_required')
        name=original['container'];check(re.fullmatch(r'sko-restore-[a-f0-9]{12}',name) is not None,'source_name_invalid')
        stage=Path(tempfile.mkdtemp(prefix='manual-insurance-install-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        def run(args,data=None,timeout=120):
            result=subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
            if result.returncode:
                found=re.search(rb'(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)',result.stderr)
                if found:status['last_sqlstate']=found.group(1).decode()
                raise RuntimeError('subprocess_failed')
            return result.stdout
        context=json.loads(run(['docker','context','inspect']))
        check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
        src=json.loads(run(['docker','inspect',name]))[0]
        check(not src['State']['Running'] and src['HostConfig']['NetworkMode']=='none' and not src['HostConfig'].get('PortBindings') and src['Config']['Image']==transport.BASE_IMAGE and src['Config']['Labels'].get('sko-purpose')=='offline-restore','source_container_mismatch')
        status['phase']='fresh_clone'
        image=run(['docker','commit',name],timeout=300).decode().strip();check(re.fullmatch(r'sha256:[a-f0-9]{64}',image) is not None,'clone_image_invalid')
        status['private_local_image']=image;clone='sko-manual-install-'+uuid.uuid4().hex[:12]
        status['container']=clone
        run(transport.clone_command(clone,image)+['-c','autovacuum=off']);created=True
        for _ in range(60):
            ready=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
            if ready.returncode==0:break
            time.sleep(1)
        else:raise RuntimeError('clone_not_ready')
        info=json.loads(run(['docker','inspect',clone]))[0]
        check(info['HostConfig']['NetworkMode']=='none' and not info['HostConfig'].get('PortBindings'),'clone_not_isolated')
        def query(sql):
            return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U','postgres','-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],("SET statement_timeout='60s';SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
        check(query('SHOW cron.launch_active_jobs;').splitlines()[-1]=='off','cron_not_disabled')
        # No DATABASE_BASELINE_SQL: preserve existing database owner and ACL too.
        status['phase']='guarded_install_rollback'
        before=query(CATALOG_SQL)
        query(install)
        check(query(CATALOG_SQL)==before,'function_catalog_not_restored')
        final=json.loads(run(['docker','inspect',name]))[0]
        check(not final['State']['Running'] and final['HostConfig']['NetworkMode']=='none' and not final['HostConfig'].get('PortBindings') and final['Config']['Image']==transport.BASE_IMAGE,'original_restore_changed')
        status.update(verified=True,phase='verified',business_rows_unchanged=True,table_catalog_unchanged=True,function_oid_acl_owner_unchanged=True,function_bodies_rolled_back=True,original_restore_preserved=True)
        code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):status['failure_code']=error.args[0]
    finally:
        if created:
            try:status['container_stopped']=subprocess.run(['docker','stop','-t','10',clone],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt):status['container_stopped']=False
            if not status.get('container_stopped'):status.update(verified=False,phase='clone_stop');code=1
        if stage:(stage/'manual-insurance-install-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
    result=('隔離復元cloneで保険料手入力契約4関数の導入・既存全給与/税/住民税/共通設定と表/OID/ACL/owner不変・全rollback確認: '+stage.name+'。保険額保存・再計算・本番適用は未実施。') if status.get('verified') else ('保険料契約の隔離導入検証は未完了（段階: '+status.get('phase','準備')+'）。元復元DB・本番・保険額は変更していません。')
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__':sys.exit(main())
