#!/usr/bin/env python3
"""Read-only native SET ROLE preflight. No install, owner/grant/reset operations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import owner_cli_database_capture as cli
import owner_database_capture as capture

SQL = r"""BEGIN READ ONLY;
SET LOCAL statement_timeout='20s';
SET LOCAL lock_timeout='3s';
SELECT jsonb_build_object('phase','before','session_is_cli',session_user LIKE 'cli_login_%','current_is_session',current_user=session_user,'member_postgres',pg_has_role(session_user,'postgres','MEMBER'),'can_set_postgres',pg_has_role(session_user,'postgres','SET'),'initial_database_create',has_database_privilege(current_user,current_database(),'CREATE'));
SET LOCAL ROLE postgres;
SELECT jsonb_build_object('phase','after','current_is_postgres',current_user='postgres','session_still_cli',session_user LIKE 'cli_login_%','read_only',current_setting('transaction_read_only')='on','database_owner_postgres',(SELECT pg_get_userbyid(datdba)='postgres' FROM pg_database WHERE datname=current_database()),'database_create',has_database_privilege(current_user,current_database(),'CREATE'),'public_schema_create',has_schema_privilege(current_user,'public','CREATE'),'authenticator_exists',to_regrole('authenticator') IS NOT NULL,'anon_exists',to_regrole('anon') IS NOT NULL,'authenticated_exists',to_regrole('authenticated') IS NOT NULL,'new_schemas_absent',to_regnamespace('company_allowance_identity_private') IS NULL AND to_regnamespace('company_common_allowance_private') IS NULL,'unit_functions_owned_by_postgres',(SELECT count(*)=2 AND bool_and(pg_get_userbyid(proowner)='postgres') FROM pg_proc WHERE oid IN(to_regprocedure('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)'),to_regprocedure('payroll_unit_private.read_conditions(uuid,uuid,date)'))),'unit_sources_match',coalesce((SELECT md5(prosrc)='5c51172a6169beb90a7ddbb6ae443cd6' FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)')),false) AND coalesce((SELECT md5(prosrc)='cf298ba4b1e848ab89a67623f7466bcd' FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.read_conditions(uuid,uuid,date)')),false));
ROLLBACK;
"""

def validate(stdout):
    rows=[json.loads(x) for x in stdout.splitlines() if x.strip()]
    if len(rows)!=2 or rows[0].get('phase')!='before' or rows[1].get('phase')!='after':
        raise capture.CaptureFailure('result_shape_invalid')
    expected_after={'phase','current_is_postgres','session_still_cli','read_only','database_owner_postgres','database_create','public_schema_create','authenticator_exists','anon_exists','authenticated_exists','new_schemas_absent','unit_functions_owned_by_postgres','unit_sources_match'}
    if set(rows[0])!={'phase','session_is_cli','current_is_session','member_postgres','can_set_postgres','initial_database_create'} or set(rows[1])!=expected_after:
        raise capture.CaptureFailure('result_keys_invalid')
    for row in rows:
        if any(not isinstance(v,bool) for k,v in row.items() if k!='phase'):
            raise capture.CaptureFailure('result_values_invalid')
    required=('session_is_cli','current_is_session','member_postgres','can_set_postgres')
    if not all(rows[0].get(k) is True for k in required) or not all(v is True for k,v in rows[1].items() if k!='phase'):
        raise capture.CaptureFailure('role_or_prerequisite_guard_failed')
    return rows

def run():
    os.umask(0o077)
    if sys.platform!='darwin': raise capture.CaptureFailure('mac_required')
    cert=Path.home()/'Downloads'/'prod-ca-2021.crt'
    if not cert.is_file() or cert.is_symlink(): raise capture.CaptureFailure('certificate_invalid')
    root=Path.home()/'SKO-source-backups'
    if any(p.is_symlink() for p in [root,*root.parents]): raise capture.CaptureFailure('private_path_invalid')
    root.mkdir(mode=0o700,exist_ok=True)
    if root.stat().st_mode & 0o077: raise capture.CaptureFailure('private_permissions_invalid')
    psql=capture.tool('psql')
    version=subprocess.run(['supabase','--version'],capture_output=True,text=True,check=True,timeout=15)
    if version.stdout.strip()!='2.120.0': raise capture.CaptureFailure('cli_version_changed')
    stage=Path(tempfile.mkdtemp(prefix='common-role-preflight-',dir=root))
    state={'verified':False,'app_data_changed':False,'grants_changed':False,'owners_changed':False,'database_password_requested':False,'cli_may_prepare_temporary_login':True}
    try:
        work=stage/'private-cli'; (work/'supabase').mkdir(parents=True,mode=0o700)
        (work/'supabase'/'config.toml').write_text('project_id = "sko-role-readonly"\n[db]\nmajor_version = 17\n')
        url,password=cli.obtain_connection(work)
        env={k:v for k,v in os.environ.items() if not k.startswith('PG') and not k.startswith('SUPABASE_') and k not in ('DB_PASSWORD','DEBUG')}
        env.update(capture.endpoint(url,cli_login=True),PGPASSWORD=password,PGSSLMODE='verify-full',PGSSLROOTCERT=str(cert),PGCONNECT_TIMEOUT='15',PGAPPNAME='sko-common-role-readonly')
        try:
            r=subprocess.run([psql,'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1','-f','-'],input=SQL,text=True,capture_output=True,env=env,timeout=60)
        finally:
            password=None; env.pop('PGPASSWORD',None)
        (stage/'private-errors.log').write_text(r.stderr)
        if r.returncode: raise capture.CaptureFailure('readonly_role_sql_failed')
        state['checks']=validate(r.stdout); state['verified']=True
    finally:
        (stage/'preflight-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
    return stage

def main():
    try:
        stage=run(); result=f'同一 READ ONLY 接続で既存 postgres SET ROLE・所有者・共通原本条件を確認: {stage.name}。本番導入・権限付与・所有者変更なし。'; code=0
    except (Exception,KeyboardInterrupt) as e:
        reason=e.code if isinstance(e,capture.CaptureFailure) else 'preflight_failed'
        result=f'読取権限確認は未完了（{reason}）。本番導入・権限付与・所有者変更なし。'; code=1
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code
if __name__=='__main__': raise SystemExit(main())
