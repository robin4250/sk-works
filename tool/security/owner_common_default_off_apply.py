#!/usr/bin/env python3
"""REVIEW ONLY: bounded native production default-OFF installer. Never auto-retry/undo."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import owner_cli_database_capture as cli
import owner_database_capture as capture
import owner_external_config_capture as external
import owner_common_role_preflight as roles
import generate_private_unused_undo as connector

HASHES={
'company_common_default_off_install.sql.review-only':'f1f03b42fc2d57266606fb36e639edb931154c674fad43b04360f7cb878deb54',
'fresh_checkpoint_capture.sql.review-only':'866f55505ca6a6c29cc097da5109505c41d8dbdaee28ffbb27859750ce368a99',
'postflight.sql.review-only':'73e0c3b2e39f57c10eb71e3adc1fc982c5a61844ce3de546a6b835ae6b48780d',
'generate_private_unused_undo.py':'ce9163e91bb831d3c4b959c05ece4909f0da1c776bf9f999e6f869f290ba7c23',
'common_payroll_unused_undo.py':'a729ec15fd553e33d613da6ea1ca42f96498fc992b698719ea5b3a0d6734c185',
'owner_payroll_common_rehearsal.py':'eb8253168195780ccb8b22aacd00471e4ff8760b7899c0b62d1bbd5f77eab41d',
'owner_expense_off_rehearsal.py':'6c3cf1078238d9bbaa9a3b767c20f779e7bcdf0f45712a861271bedcdda25e1a',
'owner_database_capture.py':'15875c927d90364f8dec1973f5fb1661dc12b9f5242aee5175203f7cb8a8702d',
'owner_cli_database_capture.py':'e4f206b3dab91f98295f2f2a1688a02cc74adb80d00d6262a3f3ce4cc9a300e0',
'owner_external_config_capture.py':'dd63acf0dbad1f2901fc22cee443711dd450edf96e60db12fdfd958a743abb7e',
'owner_common_role_preflight.py':'6c54a78eeb0ca59bc68581d6c010a1bf9cacee674c839e64a3922ad771709e1e',
}

def check(value,code):
    if not value: raise capture.CaptureFailure(code)

def private_new(path,data=b''):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as f:f.write(data)

def quote_path(path):
    text=str(path)
    check('\n' not in text and '\r' not in text,'path_invalid')
    return "'"+text.replace('\\','\\\\').replace("'","\\'")+"'"

def driver(stage,work):
    # All artifacts are exact reviewed bytes, executed by one native psql session.
    # Role lasts for this session only; session_user remains the CLI login.
    q=quote_path
    guard="DO $native_role$ BEGIN IF session_user NOT LIKE 'cli_login_%' OR current_user <> 'postgres' OR NOT pg_has_role(session_user,'postgres','SET') OR NOT has_database_privilege(current_user,current_database(),'CREATE') OR NOT has_schema_privilege(current_user,'public','CREATE') OR NOT (SELECT pg_get_userbyid(datdba)='postgres' FROM pg_database WHERE datname=current_database()) OR to_regrole('authenticator') IS NULL OR to_regrole('anon') IS NULL OR to_regrole('authenticated') IS NULL OR NOT pg_has_role(session_user,'postgres','MEMBER') OR to_regnamespace('company_allowance_identity_private') IS NOT NULL OR to_regnamespace('company_common_allowance_private') IS NOT NULL OR (SELECT count(*)<>2 OR NOT bool_and(pg_get_userbyid(proowner)='postgres') FROM pg_proc WHERE oid IN(to_regprocedure('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)'),to_regprocedure('payroll_unit_private.read_conditions(uuid,uuid,date)'))) OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)')) IS DISTINCT FROM '5c51172a6169beb90a7ddbb6ae443cd6' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.read_conditions(uuid,uuid,date)')) IS DISTINCT FROM 'cf298ba4b1e848ab89a67623f7466bcd' THEN RAISE EXCEPTION 'native effective role guard'; END IF; END $native_role$;\n"
    return "SET statement_timeout='180s'; SET lock_timeout='3s';\n"+roles.SQL+"\nSET ROLE postgres;\n"+guard+\
      '\\o '+q(stage/'private-before-checkpoint.json')+'\n\\i '+q(work/'fresh_checkpoint_capture.sql.review-only')+'\n'+\
      '\\o '+q(stage/'private-installed-checkpoints.json')+'\n\\i '+q(work/'company_common_default_off_install.sql.review-only')+'\n'+\
      '\\o '+q(stage/'private-postflight.json')+'\n\\i '+q(work/'postflight.sql.review-only')+"\nSELECT jsonb_build_object('postflight',true);\n"+\
      '\\o '+q(stage/'private-after-checkpoint.json')+'\n\\i '+q(work/'fresh_checkpoint_capture.sql.review-only')+'\n'

def verify_outputs(stage):
    proof=json.loads((stage/'private-installed-checkpoints.json').read_text())
    before=json.loads((stage/'private-before-checkpoint.json').read_text())
    after=json.loads((stage/'private-after-checkpoint.json').read_text())
    check(proof.get('schema')==1 and proof.get('source_hashes')==connector.undo.common.EXPECTED,'proof_source_invalid')
    check(before==proof.get('before') and after==proof.get('after'),'checkpoint_mismatch')
    check(json.loads((stage/'private-postflight.json').read_text())=={'postflight':True},'postflight_receipt_invalid')
    return proof

def run():
    os.umask(0o077)
    check(sys.platform=='darwin','mac_required')
    work=Path(__file__).resolve().parent
    for name,expected in HASHES.items():
        path=work/name;check(path.is_file() and not path.is_symlink() and capture.digest(path)==expected,'reviewed_artifact_mismatch')
    root=Path.home()/'SKO-source-backups';external.private_path(root,directory=True)
    marker=root/'common-default-off-production-attempt.json'
    check(not marker.exists() and not marker.is_symlink(),'prior_attempt_requires_fresh_lookup')
    cert=Path.home()/'Downloads'/'prod-ca-2021.crt'
    check(cert.is_file() and not cert.is_symlink(),'certificate_invalid')
    psql=capture.tool('psql')
    # Reuse frozen readonly external capture: verifies old backup hashes before/after.
    ext=external.run_capture(root,'external-config-va7rktv6')
    stage=Path(tempfile.mkdtemp(prefix='common-production-apply-',dir=root))
    state={'schema':1,'verified':False,'install_attempted':False,'commit_state':'not_attempted','activation_written':False,'publication_written':False,'payroll_recalculated':False,'automatic_undo':False,'external_before':ext.name}
    def status():
        path=stage/'apply-status.json'
        path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n');path.chmod(0o600)
    status()
    try:
        cliwork=stage/'private-cli';(cliwork/'supabase').mkdir(parents=True,mode=0o700)
        (cliwork/'supabase'/'config.toml').write_text('project_id = "sko-common-default-off"\n[db]\nmajor_version = 17\n')
        url,password=cli.obtain_connection(cliwork)
        env={k:v for k,v in os.environ.items() if not k.startswith('PG') and not k.startswith('SUPABASE_') and k not in ('DB_PASSWORD','DEBUG')}
        env.update(capture.endpoint(url,cli_login=True),PGPASSWORD=password,PGSSLMODE='verify-full',PGSSLROOTCERT=str(cert),PGCONNECT_TIMEOUT='15',PGAPPNAME='sko-common-default-off')
        for name in ('private-before-checkpoint.json','private-installed-checkpoints.json','private-postflight.json','private-after-checkpoint.json','private-session-output.json','private-errors.log'):
            private_new(stage/name)
        private_new(stage/'reviewed-driver.psql',driver(stage,work).encode())
        # Exclusive persistent marker prevents every automated retry, including an
        # interrupted connection where COMMIT may have succeeded but output was lost.
        private_new(marker,json.dumps({'stage':stage.name,'commit_state':'requires_private_result_or_fresh_lookup','install_sha256':HASHES['company_common_default_off_install.sql.review-only']}).encode())
        state.update(install_attempted=True,commit_state='unknown');status()
        try:
            with (stage/'private-session-output.json').open('wb') as out,(stage/'private-errors.log').open('wb') as err:
                result=subprocess.run([psql,'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1','-f',str(stage/'reviewed-driver.psql')],stdout=out,stderr=err,env=env,timeout=600,stdin=subprocess.DEVNULL)
        finally:
            password=None;env.pop('PGPASSWORD',None)
        check(result.returncode==0,'apply_or_postflight_failed_fresh_lookup_required')
        # Role preflight JSON, emitted before any artifact, must pass too.
        roles.validate((stage/'private-session-output.json').read_text())
        verify_outputs(stage)
        state['commit_state']='committed_verified'
        connector.generate(stage/'private-installed-checkpoints.json',stage/'private-unused-undo.sql')
        state['private_unused_undo_generated']=True
        post=external.run_capture(root,'external-config-va7rktv6')
        state.update(external_after=post.name,verified=True,phase='default_off_installed')
        return stage
    finally:
        status()

def main():
    try:
        stage=run();result=f'共通手当の限定 default-OFF 導入・private checkpoint・未使用 undo 保存・外部設定不変を確認: {stage.name}。有効化・給与再計算は未実施。';code=0
    except (Exception,KeyboardInterrupt) as e:
        reason=e.code if isinstance(e,capture.CaptureFailure) else 'apply_not_confirmed'
        result=f'共通手当の本番導入完了は未確認（{reason}）。再実行禁止。接続切断後も COMMIT 済みの可能性があるため新規読取で状態確認が必要です。';code=1
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code
if __name__=='__main__':raise SystemExit(main())
