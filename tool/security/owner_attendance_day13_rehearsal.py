#!/usr/bin/env python3
"""Rehearse one user-confirmed attendance date in a separate offline restored DB."""
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

SOURCE = 'database-restore-01qyi5py'
BASE_IMAGE = 'supabase/postgres@sha256:b3bfedb107413abb3b8cb0d0874b0414a1dceb3d55bc0c778de6ad22d1f7dc86'
# Read from production catalog on 2026-10-20. pg_dump without --create does
# not restore the database object's owner/ACL. Apply ONLY to the offline clone.
DATABASE_BASELINE_SQL = '''DO $database_baseline$
BEGIN
 IF current_database()<>'postgres' OR current_user<>'supabase_admin'
 OR (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database()) NOT IN ('supabase_admin','postgres')
 THEN RAISE EXCEPTION 'unexpected clone database identity'; END IF;
 IF EXISTS(SELECT 1 FROM pg_database d CROSS JOIN LATERAL aclexplode(coalesce(d.datacl,acldefault('d',d.datdba))) a
 WHERE d.datname=current_database() AND a.grantee<>0 AND pg_get_userbyid(a.grantee) NOT IN
 ('postgres','supabase_admin','supabase_etl_admin','supabase_storage_admin','dashboard_user'))
 THEN RAISE EXCEPTION 'unknown clone database grant'; END IF;
 ALTER DATABASE postgres OWNER TO postgres;
 REVOKE ALL ON DATABASE postgres FROM PUBLIC,postgres,supabase_admin,supabase_etl_admin,supabase_storage_admin,dashboard_user;
 GRANT TEMPORARY,CONNECT ON DATABASE postgres TO PUBLIC;
 GRANT ALL ON DATABASE postgres TO postgres;
 GRANT CREATE ON DATABASE postgres TO supabase_etl_admin,supabase_storage_admin;
 GRANT ALL ON DATABASE postgres TO dashboard_user;
END $database_baseline$;
DO $verify_database_baseline$
DECLARE actual jsonb; expected jsonb;
BEGIN
 SELECT jsonb_agg(jsonb_build_array(CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
 a.privilege_type,pg_get_userbyid(a.grantor),a.is_grantable) ORDER BY
 CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,a.privilege_type) INTO actual
 FROM pg_database d CROSS JOIN LATERAL aclexplode(d.datacl) a WHERE d.datname=current_database();
 SELECT jsonb_agg(jsonb_build_array(r,p,'postgres',false) ORDER BY r,p) INTO expected FROM (VALUES
 ('PUBLIC','CONNECT'),('PUBLIC','TEMPORARY'),('postgres','CREATE'),('postgres','CONNECT'),('postgres','TEMPORARY'),
 ('supabase_etl_admin','CREATE'),('supabase_storage_admin','CREATE'),
 ('dashboard_user','CREATE'),('dashboard_user','CONNECT'),('dashboard_user','TEMPORARY')) x(r,p);
 IF actual IS DISTINCT FROM expected OR NOT has_schema_privilege('postgres','public','CREATE')
 THEN RAISE EXCEPTION 'clone database owner/ACL differs from observed production'; END IF;
END $verify_database_baseline$;'''

def clone_command(name,image):
    return ['docker','run','-d','--name',name,'--network=none','--user=postgres','--no-healthcheck',
            '--label','sko-purpose=attendance-day13-rehearsal','--entrypoint','postgres',image,
            '-D','/tmp/sko-pg','-c','listen_addresses=','-c','unix_socket_directories=/tmp',
            '-c','shared_preload_libraries=pg_cron,pg_stat_statements','-c','cron.database_name=postgres',
            '-c','cron.launch_active_jobs=off','-c','wal_level=logical']


def main():
    os.umask(0o077)
    stage=None; clone=None; started=False
    status={'schema':1,'verified':False,'production_connected':False,'production_rows_repaired':False}
    try:
        if sys.platform!='darwin': raise RuntimeError('mac_required')
        if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'): raise RuntimeError('docker_override_refused')
        root=Path.home()/'SKO-source-backups'
        source=root/SOURCE
        if any(p.is_symlink() for p in (source,*source.parents)) or root.stat().st_mode&0o077:
            raise RuntimeError('private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        if not original.get('archive_restore_verified') or not original.get('container_stopped'):
            raise RuntimeError('verified_stopped_source_required')
        name=original['container']
        if not re.fullmatch(r'sko-restore-[a-f0-9]{12}',name): raise RuntimeError('source_name_invalid')
        bundle=json.loads((Path(__file__).parent/'attendance_clone_bundle.json').read_text())
        if hashlib.sha256(bundle['files']['scenario.sql'].encode()).hexdigest()!='11194355a9aeaf99b08180f944e42f52b2d657067e7b4d28502094107fbce972':
            raise RuntimeError('reviewed_scenario_mismatch')
        stage=Path(tempfile.mkdtemp(prefix='attendance-day13-rehearsal-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=120):
                return subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                                      stdout=subprocess.PIPE,stderr=errors,check=True,timeout=timeout).stdout
            context=json.loads(run(['docker','context','inspect']))
            if not context[0]['Endpoints']['docker']['Host'].startswith('unix://'): raise RuntimeError('remote_docker_refused')
            src=json.loads(run(['docker','inspect',name]))[0]
            if src['State']['Running'] or src['HostConfig']['NetworkMode']!='none' or src['Config']['Image']!=BASE_IMAGE:
                raise RuntimeError('source_container_mismatch')
            if src['Config']['Labels'].get('sko-purpose')!='offline-restore': raise RuntimeError('source_label_mismatch')
            print('復元成功済みDBをローカルで複製します。元DB・バックアップは保持します。',flush=True)
            status['phase']='clone'
            image=run(['docker','commit',name],timeout=300).decode().strip()
            if not re.fullmatch(r'sha256:[a-f0-9]{64}',image): raise RuntimeError('clone_image_invalid')
            status['private_local_image']=image
            clone='sko-attendance-'+uuid.uuid4().hex[:12]
            status['container']=clone
            run(clone_command(clone,image)); started=True
            for attempt in range(60):
                result=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],
                    env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if result.returncode==0: break
                time.sleep(1)
            else: raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0]
            if info['HostConfig']['NetworkMode']!='none' or info['HostConfig'].get('PortBindings'):
                raise RuntimeError('clone_not_isolated')
            def query(sql,role='postgres'):
                return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres',
                            '-q','-A','-t','-v','ON_ERROR_STOP=1'],
                           ("SET statement_timeout='30s'; SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
            if query('SHOW cron.launch_active_jobs;').splitlines()[-1]!='off': raise RuntimeError('cron_not_disabled')
            status['phase']='database_properties'
            query(DATABASE_BASELINE_SQL,role='supabase_admin')
            status['database_owner_acl_matched']=True
            # -q avoids command status lines in JSON/digest responses.
            def value(sql):
                output=query(sql)
                return output.splitlines()[-1]
            status['phase']='source_preflight'
            if value("SELECT to_regprocedure('private.payroll_draft_source_fingerprint(uuid,uuid,date)') IS NULL;")!='t':
                raise RuntimeError('source_fingerprint_already_present')
            for filename,content in bundle['files'].items(): (stage/filename).write_text(content)
            before=json.loads(value(bundle['inventory_sql']))
            status['phase']='actual_attendance'
            print('隔離DBだけで13日1人工を既存管理RPCへ渡し、給与・請求書3日と元時刻・既存履歴を検証して全て戻します。',flush=True)
            query('BEGIN;\n'+bundle['files']['source_fingerprint.sql']+'\n'+bundle['files']['scenario.sql']+'\nROLLBACK;')
            status['phase']='full_table_rollback'
            after=json.loads(value(bundle['inventory_sql']))
            if after!=before: raise RuntimeError('full_table_rollback_mismatch')
            if value("SELECT to_regprocedure('private.payroll_draft_source_fingerprint(uuid,uuid,date)') IS NULL;")!='t':
                raise RuntimeError('source_function_rollback_mismatch')
            (stage/'before-table-hashes.json').write_text(json.dumps(before))
            (stage/'after-table-hashes.json').write_text(json.dumps(after))
            status.update(verified=True,phase='verified',real_jwt_verified=False,
                          original_timestamp_precision_preserved=True,attendance_dates_after=3,
                          invoice_quantity_after=3,all_table_rows_rollback_verified=True,
                          rollback_table_count=len(before))
        result=f'隔離実DBで13日1人工・給与3日・請求書3日・元時刻保持・既存履歴保護・全業務表rollback成功: {stage.name}。本番修復・実HTTP/JWT・新アプリ配布は未実施。'
        code=0
    except (Exception,KeyboardInterrupt):
        result='出勤13日の隔離検証は未完了（段階: '+status.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。'
        code=1
    finally:
        if started:
            try:
                stopped=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
                status['container_stopped']=stopped.returncode==0
            except (Exception,KeyboardInterrupt): status['container_stopped']=False
            if not status['container_stopped']:
                status.update(verified=False,phase='clone_stop')
                result='隔離検証DBの停止を確認できません。段階: clone_stop。元の復元DB・バックアップ・本番は変更していません。停止対象は今回の専用cloneだけです。'
                code=1
        if stage: (stage/'attendance-rehearsal-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code


if __name__=='__main__': raise SystemExit(main())
