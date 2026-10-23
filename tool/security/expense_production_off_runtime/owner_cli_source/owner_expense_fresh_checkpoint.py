#!/usr/bin/env python3
"""Fixed read-only fresh checkpoint via existing CLI temporary DB connection."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import owner_cli_database_capture as cli
capture=cli.capture
TABLES=('public.payment_certificates','private.expense_claims','private.expense_settlement_choices','private.expense_amount_consumptions','private.expense_document_snapshots')
OLD={'private.expense_cost_finalize()':'538cdf28ac2aefb36040f799dced3078','private.read_expense_document(text,uuid)':'194b68f6f3933850b16ddb3e8eae633d','private.refresh_automatic_payment_certificate(uuid,uuid,date)':'499b5154730aeef5ae53c763ba82a421'}


def build_query(queries):
    count=' UNION ALL '.join('SELECT count(*) n FROM (SELECT 1 FROM '+t+' LIMIT 10001) bounded' for t in TABLES)
    size=' UNION ALL '.join('SELECT coalesce(sum(octet_length(to_jsonb(x)::text)),0) n FROM '+t+' x' for t in TABLES)
    return "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';SET ROLE postgres;\nDO $limits$ BEGIN IF (SELECT sum(n) FROM ("+count+") x)>10000 THEN RAISE EXCEPTION 'checkpoint row limit exceeded'; END IF;IF (SELECT sum(n) FROM ("+size+") x)>16777216 THEN RAISE EXCEPTION 'checkpoint byte limit exceeded';END IF;END $limits$;\nSELECT jsonb_build_object('schema',1,'captured_at',clock_timestamp(),'read_only',current_setting('transaction_read_only'),'before',("+queries['catalogSql']+"),'business',("+queries['defaultOffBusinessHashSql']+"),'exact_target_count',(SELECT count(*) FROM public.payment_certificates p WHERE md5(to_jsonb(p)::text)='558302f271e0033a2a76299c16ea8b78' AND status='draft'),'global_v2_or_basis_count',(SELECT count(*) FROM public.payment_certificates WHERE snapshot?'expense_cost_direction_v2' OR snapshot?'expense_cost_basis'),'converter_installed',to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)') IS NOT NULL,'conversion_audit_installed',to_regclass('private.expense_payment_direction_conversions') IS NOT NULL,'rollout_installed',to_regprocedure('private.expense_direction_v2_client_rollout_verified(uuid)') IS NOT NULL);COMMIT;"


def validate(value):
    if value.get('schema')!=1 or value.get('read_only')!='on' or value.get('exact_target_count')!=1 or value.get('global_v2_or_basis_count')!=0 or any(value.get(k) is not False for k in ('converter_installed','conversion_audit_installed','rollout_installed')):raise RuntimeError('fresh_scope_changed')
    if not re.fullmatch(r'[a-f0-9]{32}',value.get('business','')):raise RuntimeError('financial_hash_invalid')
    actual={f['signature']:f['source_md5'] for f in value['before']['functions']}
    if actual!=OLD:raise RuntimeError('existing_code_guard_changed')


def main():
    os.umask(0o077);stage=None;env=None;password=None;state={'schema':1,'verified':False,'application_data_mutations':False,'deployment_performed':False,'conversion_performed':False,'cli_temporary_role_requested':True};code=1
    try:
        if sys.platform!='darwin':raise RuntimeError('mac_required')
        certificate=Path.home()/'Downloads/prod-ca-2021.crt'
        if not certificate.is_file() or certificate.is_symlink() or certificate.stat().st_size>1048576:raise RuntimeError('certificate_required')
        root=Path.home()/'SKO-source-backups'
        if any(p.is_symlink() for p in (root,*root.parents)) or not root.is_dir() or root.stat().st_mode&0o077:raise RuntimeError('private_root_required')
        psql=capture.tool('psql')
        version=subprocess.run(['supabase','--version'],capture_output=True,text=True,check=True,timeout=15)
        if version.stdout.strip()!='2.120.0':raise RuntimeError('cli_version_changed')
        stage=Path(tempfile.mkdtemp(prefix='expense-fresh-checkpoint-',dir=root));state['phase']='cli_temporary_connection'
        with tempfile.TemporaryDirectory(prefix='sko-cli-checkpoint-') as folder:
            work=Path(folder);(work/'supabase').mkdir(mode=0o700);(work/'supabase/config.toml').write_text('project_id = "sko-private-capture"\n[db]\nmajor_version = 17\n')
            url,password=cli.obtain_connection(work)
            env={k:v for k,v in os.environ.items() if not k.startswith('PG')};env.update(capture.endpoint(url,cli_login=True),PGPASSWORD=password,PGSSLMODE='verify-full',PGSSLROOTCERT=str(certificate),PGCONNECT_TIMEOUT='10',PGOPTIONS='-c default_transaction_read_only=on',PGPASSFILE='/dev/null',PGSERVICEFILE='/dev/null')
            state['phase']='fixed_read_only_capture'
            queries=json.loads((Path(__file__).parent/'capture_queries.json').read_text())
            result=subprocess.run([psql,'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],input=build_query(queries).encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=120)
            if result.returncode:
                found=re.search(rb'(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)',result.stderr)
                if found:state['last_sqlstate']=found.group(1).decode()
                raise RuntimeError('readonly_capture_failed')
            if len(result.stdout)>16777216:raise RuntimeError('capture_output_too_large')
            value=json.loads(result.stdout);validate(value)
            target=stage/'private-fresh-before.json';target.write_text(json.dumps(value))
            state.update(verified=True,phase='verified',scope_guard_matched=True,readonly_verified=True,artifact_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),artifact_bytes=target.stat().st_size);code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):state['failure_code']=error.args[0]
    finally:
        password=None
        if env:env.pop('PGPASSWORD',None)
        if stage:(stage/'checkpoint-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('経費の実対象・既存コード一致を読取専用で再確認し、最新の非公開checkpointを保存: '+stage.name+'。' if state['verified'] else '経費の最新checkpoint取得は未完了（段階: '+state.get('phase','準備')+'）。')+'導入・gate変更・下書き変換は行っていません。'
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__':sys.exit(main())
