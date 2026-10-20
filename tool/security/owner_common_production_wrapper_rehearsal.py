#!/usr/bin/env python3
"""Verify only the new reviewed production wrapper on a new offline clone."""
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
import common_payroll_unused_undo as undo
import build_review_artifacts as builder
import generate_private_unused_undo as connector

INSTALL_HASH='f1f03b42fc2d57266606fb36e639edb931154c674fad43b04360f7cb878deb54'
POSTFLIGHT_HASH='73e0c3b2e39f57c10eb71e3adc1fc982c5a61844ce3de546a6b835ae6b48780d'


def check(value,code):
    if not value:raise RuntimeError(code)


def reviewed_install(root):
    sql=(root/'company_common_default_off_install.sql.review-only').read_text()
    check(hashlib.sha256(sql.encode()).hexdigest()==INSTALL_HASH,'install_hash_mismatch')
    check(sql==builder.build(json.loads((root/'common_payroll_sources.json').read_text())),'install_builder_mismatch')
    check(hashlib.sha256((root/'postflight.sql.review-only').read_bytes()).hexdigest()==POSTFLIGHT_HASH,'postflight_hash_mismatch')
    return sql


def main():
    os.umask(0o077);stage=None;clone=None;clone_id=None;started=False;code=1
    state={'schema':1,'verified':False,'production_connected':False,'original_restore_changed':False,'wrapper_only':True,'activation_written':False,'payroll_recalculated':False,'real_jwt_repeated':False}
    try:
        check(sys.platform=='darwin','mac_required')
        check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        work=Path(__file__).parent;install=reviewed_install(work)
        root=Path.home()/'SKO-source-backups';source=root/transport.SOURCE
        check(not any(p.is_symlink() for p in (source,*source.parents)) and not root.stat().st_mode&0o077,'private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        check(original.get('archive_restore_verified') and original.get('container_stopped'),'verified_stopped_source_required')
        original_name=original['container'];check(re.fullmatch(r'sko-restore-[a-f0-9]{12}',original_name) is not None,'source_name_invalid')
        stage=Path(tempfile.mkdtemp(prefix='common-production-wrapper-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=180):
                return subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,stdout=subprocess.PIPE,stderr=errors,check=True,timeout=timeout).stdout
            context=json.loads(run(['docker','context','inspect']))
            check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
            def source_check():
                info=json.loads(run(['docker','inspect',original_name]))[0]
                check(not info['State']['Running'] and info['HostConfig']['NetworkMode']=='none' and not info['HostConfig'].get('PortBindings') and info['Config']['Image']==transport.BASE_IMAGE and info['Config']['Labels'].get('sko-purpose')=='offline-restore','source_container_mismatch')
            source_check();state['phase']='clone'
            image=run(['docker','commit',original_name],timeout=300).decode().strip()
            check(re.fullmatch(r'sha256:[a-f0-9]{64}',image) is not None,'clone_image_invalid')
            state['private_local_image']=image;clone='sko-common-'+uuid.uuid4().hex[:12];state['container']=clone
            args=transport.clone_command(clone,image);args[1]='create';args.remove('-d')
            clone_id=run(args).decode().strip();check(re.fullmatch(r'[a-f0-9]{64}',clone_id) is not None,'clone_container_id_invalid')
            started=True;run(['docker','start',clone_id])
            for _ in range(60):
                r=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if r.returncode==0:break
                time.sleep(1)
            else:raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0]
            check(info['HostConfig']['NetworkMode']=='none' and not info['HostConfig'].get('PortBindings'),'clone_not_isolated')
            def query(sql,role='postgres'):
                return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1'],("SET statement_timeout='180s';SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
            def value(sql):return query(sql).splitlines()[-1]
            check(value('SHOW cron.launch_active_jobs;')=='off','cron_not_disabled')
            state['phase']='database_properties';query(transport.DATABASE_BASELINE_SQL,role='supabase_admin')
            def capture():
                catalog=json.loads(value(undo.CATALOG_SNAPSHOT_SQL));functions=json.loads(value(undo.FUNCTIONS_SQL))
                business=value(undo.common.BUSINESS_SQL)
                all_rows=value(undo.common.BUSINESS_SQL.replace(undo.common.SCOPES,undo.CATALOG_SCOPE))
                return {'checkpoint':undo.checkpoint(catalog,functions,business),'all_application_rows_hash':all_rows}
            before=capture();(stage/'original-checkpoint.json').write_text(json.dumps(before))
            state['phase']='reviewed_wrapper_install_commit'
            (stage/'reviewed-install.sql').write_text(install)
            output=query(install);proof=json.loads(output)
            check(proof.get('schema')==1 and proof.get('source_hashes')==undo.common.EXPECTED,'private_checkpoint_shape_invalid')
            check(proof['before']==before['checkpoint'] and proof['all_application_rows_hash']==before['all_application_rows_hash'],'fresh_checkpoint_differs_from_original')
            private_path=stage/'private-installed-checkpoints.json';private_path.write_text(json.dumps(proof))
            state.update(install_committed=True,fresh_private_checkpoint_verified=True)
            state['phase']='private_unused_undo_generation';undo_path=stage/'reviewed-unused-undo.sql'
            connector.generate(private_path,undo_path)
            check(undo_path.stat().st_mode&0o777==0o600,'private_unused_undo_permissions_invalid')
            state['phase']='reviewed_postflight';query((work/'postflight.sql.review-only').read_text())
            current=capture();check(current['checkpoint']==proof['after'] and current['all_application_rows_hash']==before['all_application_rows_hash'],'postflight_changed_checkpoint')
            state['phase']='reviewed_unused_undo_commit';query(undo_path.read_text())
            state['phase']='original_checkpoint_comparison';check(capture()==before,'committed_wrapper_undo_not_exact')
            source_check()
            for name in ('original-checkpoint.json','reviewed-install.sql','private-installed-checkpoints.json','reviewed-unused-undo.sql'):
                data=(stage/name).read_bytes();state.setdefault('artifacts',{})[name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
            state.update(verified=True,phase='verified',postflight_verified=True,unused_undo_committed=True,original_catalog_restored=True,original_application_rows_unchanged=True,sequence_counters_restored=False,oid_counter_restored=False);code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):state['failure_code']=error.args[0]
        state['verified']=False;code=1
    finally:
        if started:
            try:state['container_stopped']=subprocess.run(['docker','stop','-t','10',clone_id],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt):state['container_stopped']=False
            if not state['container_stopped']:state.update(verified=False,phase='clone_stop');code=1
        if stage:(stage/'wrapper-rehearsal-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('隔離実DBで新しい共通手当の導入transaction・private checkpoint出力・未使用undo接続・COMMIT復元の一致を確認: '+stage.name+'。' if state['verified'] else '共通手当の新導入wrapper隔離検証は未完了（段階: '+state.get('phase','準備')+'）。')+'元の復元DB・バックアップ・本番は変更していません。'
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__':sys.exit(main())
