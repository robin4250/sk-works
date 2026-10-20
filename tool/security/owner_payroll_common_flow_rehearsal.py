#!/usr/bin/env python3
"""Rehearse original common save/publication/payroll APIs in an offline real DB clone."""
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
import owner_payroll_common_rehearsal as dependencies
from owner_payroll_common_rehearsal import transport, CATALOG_SQL, BUSINESS_SQL

SCENARIO_SHA256 = 'e7a1cf9be27089547d0909f0f3f2b2b2d9fbb40f334d321f342450f27481ad58'


def build_flow(bundle,scenario):
    if scenario.get('schema')!=1 or set(scenario)!={'schema','sql'} or not isinstance(scenario.get('sql'),str):
        raise RuntimeError('scenario_contract_mismatch')
    sql=scenario['sql']
    if hashlib.sha256(sql.encode()).hexdigest()!=SCENARIO_SHA256:
        raise RuntimeError('scenario_hash_mismatch')
    if re.search(r'^\s*(BEGIN|COMMIT|ROLLBACK|START TRANSACTION)\s*;',sql,re.I|re.M):
        raise RuntimeError('scenario_transaction_control_refused')
    installation=dependencies.build_install(bundle)
    if not installation.endswith('\nROLLBACK;'): raise RuntimeError('install_transaction_shape_mismatch')
    return installation.removesuffix('\nROLLBACK;')+'\n'+sql+'\nROLLBACK;'


def main():
    os.umask(0o077)
    stage=None; clone=None; started=False
    status={'schema':1,'verified':False,'production_connected':False,'production_activation_written':False,'production_payroll_recalculated':False,'real_jwt_verified':False}
    try:
        if sys.platform!='darwin': raise RuntimeError('mac_required')
        if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'): raise RuntimeError('docker_override_refused')
        bundle=json.loads((Path(__file__).parent/'common_payroll_sources.json').read_text())
        scenario=json.loads((Path(__file__).parent/'common_flow_scenario.json').read_text())
        install=build_flow(bundle,scenario)
        root=Path.home()/'SKO-source-backups'; source=root/transport.SOURCE
        if any(p.is_symlink() for p in (source,*source.parents)) or root.stat().st_mode&0o077: raise RuntimeError('private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        if not original.get('archive_restore_verified') or not original.get('container_stopped'): raise RuntimeError('verified_stopped_source_required')
        name=original['container']
        if not re.fullmatch(r'sko-restore-[a-f0-9]{12}',name): raise RuntimeError('source_name_invalid')
        stage=Path(tempfile.mkdtemp(prefix='payroll-common-flow-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=120):
                return subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                    stdout=subprocess.PIPE,stderr=errors,check=True,timeout=timeout).stdout
            context=json.loads(run(['docker','context','inspect']))
            if not context[0]['Endpoints']['docker']['Host'].startswith('unix://'): raise RuntimeError('remote_docker_refused')
            src=json.loads(run(['docker','inspect',name]))[0]
            if src['State']['Running'] or src['HostConfig']['NetworkMode']!='none' or src['Config']['Image']!=transport.BASE_IMAGE or src['Config']['Labels'].get('sko-purpose')!='offline-restore': raise RuntimeError('source_container_mismatch')
            status['phase']='clone'
            print('元の復元DBを保持し、通信なしの別DBで共通手当の保存・適用月・給与明細連動を検証します。',flush=True)
            image=run(['docker','commit',name],timeout=300).decode().strip()
            if not re.fullmatch(r'sha256:[a-f0-9]{64}',image): raise RuntimeError('clone_image_invalid')
            status['private_local_image']=image; clone='sko-common-flow-'+uuid.uuid4().hex[:12]; status['container']=clone
            run(transport.clone_command(clone,image)); started=True
            for attempt in range(60):
                result=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if result.returncode==0: break
                time.sleep(1)
            else: raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0]
            if info['HostConfig']['NetworkMode']!='none' or info['HostConfig'].get('PortBindings'): raise RuntimeError('clone_not_isolated')
            def query(sql,role='postgres'):
                return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1'],("SET statement_timeout='60s'; SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
            def value(sql): return query(sql).splitlines()[-1]
            if value('SHOW cron.launch_active_jobs;')!='off': raise RuntimeError('cron_not_disabled')
            status['phase']='database_properties'; query(transport.DATABASE_BASELINE_SQL,role='supabase_admin')
            before=value(CATALOG_SQL); business=value(BUSINESS_SQL)
            status['phase']='common_save_publish_rollback'; (stage/'reviewed-install-rollback.sql').write_text(install)
            output=query(install)
            result_value=json.loads(output.splitlines()[-1])
            required=['saved','published','payroll_totals_verified','public_detail_verified','tax_insurance_conditions_preserved','resident_tax_preserved','save_retry_verified','publish_retry_verified','cas_verified']
            if any(result_value.get(key) is not True for key in required): raise RuntimeError('common_flow_result_incomplete')
            (stage/'flow-result.json').write_text(json.dumps(result_value,ensure_ascii=False,indent=2))
            if value(CATALOG_SQL)!=before: raise RuntimeError('catalog_not_restored')
            if value(BUSINESS_SQL)!=business: raise RuntimeError('existing_business_changed')
            status.update(verified=True,phase='verified',catalog_restored=True,business_unchanged=True,isolated_save_publish_verified=True,**result_value)
        result=f'隔離実DBで共通支給・控除の保存→適用月公開→給料明細の内訳・合計、保険/税条件保持、再実行/CAS拒否、全rollback成功: {stage.name}。本番適用・実HTTP/JWT・実機は未実施。'; code=0
    except (Exception,KeyboardInterrupt):
        result='社内共通手当の保存・給与連動検証は未完了（段階: '+status.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。'; code=1
    finally:
        if started:
            try: status['container_stopped']=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt): status['container_stopped']=False
        if started and not status.get('container_stopped'):
            status.update(verified=False,phase='clone_stop')
            result='社内共通手当の隔離DB停止を確認できません。元の復元DB・バックアップ・本番は変更していません。'; code=1
        if stage: (stage/'common-rehearsal-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__': sys.exit(main())
