#!/usr/bin/env python3
"""Read-only recovery of immutable completed-install evidence. Never retry apply."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import owner_manual_insurance_apply as frozen

IMMUTABLE_COMMIT='84e8842ddab512b7bd7895533e63876ac18a5199'
EXPECTED_INSTALLED={
 'payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)':'dac4256f30e643c4239ee37d7510a103',
 'payroll_tax_private.read_conditions(uuid,uuid)':'a8ceb2b235f66528b3ce1fb4cad59a68',
 'payroll_tax_private.validate_conditions(jsonb)':'f74834ae3fc4081e31e646c0fab25ec8',
 'private.apply_payroll_custom_money()':'35c54dd6bcc855eb0076439c451cf7c3'}

def check(value,code):
 if not value:raise RuntimeError(code)

def private_read(path):
 check(path.is_file() and not any(p.is_symlink() for p in (path,*path.parents)) and not path.stat().st_mode&0o077 and path.stat().st_size<16777216,'private_evidence_invalid')
 return path.read_bytes()

def validate_role_evidence(text):
 rows=[json.loads(line) for line in text.splitlines() if line.strip()]
 check(len(rows)==2 and rows[1].get('phase')=='after','role_evidence_invalid')
 before_keys={'phase','session_is_cli','current_is_session','member_postgres','can_set_postgres','initial_database_create'}
 after_keys={'phase','current_is_postgres','session_still_cli','read_only','database_owner_postgres','database_create','public_schema_create','authenticator_exists','anon_exists','authenticated_exists','new_schemas_absent','unit_functions_owned_by_postgres','unit_sources_match'}
 check(rows[0].get('phase')=='before' and set(rows[0])==before_keys and set(rows[1])==after_keys,'role_evidence_invalid')
 check(all(type(value) is bool for row in rows for key,value in row.items() if key!='phase'),'role_evidence_invalid')
 check(all(rows[0][key] is True for key in ('session_is_cli','current_is_session','member_postgres','can_set_postgres')),'required_role_evidence_failed')
 expected_false={'new_schemas_absent','unit_sources_match'}
 check(all(rows[1][key] is False for key in expected_false),'common_only_diagnostic_not_expected')
 check(all(value is True for key,value in rows[1].items() if key!='phase' and key not in expected_false),'required_role_evidence_failed')
 return {key:rows[1][key] for key in sorted(expected_false)}

def verify_evidence(stage):
 names=['private-before-checkpoint.json','private-installed-checkpoints.json','private-after-checkpoint.json','private-session-output.json','apply-status.json']
 before_files={name:hashlib.sha256(private_read(stage/name)).hexdigest() for name in names}
 status=json.loads(private_read(stage/'apply-status.json'))
 check(status.get('install_attempted') is True,'install_attempt_missing')
 observed=validate_role_evidence(private_read(stage/'private-session-output.json').decode())
 proof=frozen.verify_outputs(stage)
 installed={row['signature']:row['body_hash'] for row in proof['after']['functions']}
 check(installed==EXPECTED_INSTALLED,'installed_hash_mismatch')
 for name,digest in before_files.items():check(hashlib.sha256(private_read(stage/name)).hexdigest()==digest,'source_evidence_changed')
 return proof,observed,before_files

def prepare_unused_undo(source,target):
 proof,observed,fingerprints=verify_evidence(source)
 frozen.artifacts.generate(source/'private-installed-checkpoints.json',target)
 return proof,observed,fingerprints

def run():
 os.umask(0o077)
 check(sys.platform=='darwin','mac_required')
 work=Path(__file__).parent
 manifest=json.loads((work/'loader_manifest.json').read_text())
 for name,expected in manifest['files'].items():check(hashlib.sha256((work/name).read_bytes()).hexdigest()==expected,'immutable_runtime_mismatch')
 root=Path.home()/'SKO-source-backups';frozen.external.private_path(root,directory=True)
 marker=root/'manual-insurance-production-attempt.json';marker_bytes=private_read(marker)
 record=json.loads(marker_bytes);name=record.get('stage','')
 check(re.fullmatch(r'manual-insurance-production-apply-[A-Za-z0-9_-]{1,40}',name) is not None,'attempt_stage_invalid')
 check(record.get('install_sha256')==manifest['files']['manual_insurance_install.sql.review-only'],'attempt_source_mismatch')
 source=root/name;frozen.external.private_path(source,directory=True)
 stage=Path(tempfile.mkdtemp(prefix='manual-insurance-production-recovery-',dir=root))
 state={'schema':1,'verified':False,'source_commit':IMMUTABLE_COMMIT,'apply_retried':False,'database_connected':False,
   'roles_changed':False,'claims_changed':False,'amounts_changed':False,'original_marker_or_status_changed':False,'undo_executed':False}
 try:
  proof,observed,fingerprints=prepare_unused_undo(source,stage/'private-unused-undo.sql')
  state.update(checkpoints_verified=True,role_evidence_verified=True,common_only_prerequisites=observed,expected_installed_hashes=EXPECTED_INSTALLED,source_evidence_sha256=fingerprints)
  # Offline generation only, into a NEW recovery directory. Never run SQL.
  state['private_unused_undo_generated']=True
  ext=frozen.external.run_capture(root,'external-config-va7rktv6')
  state['readonly_external_after']=ext.name
  check(private_read(marker)==marker_bytes,'original_marker_changed')
  for filename,digest in fingerprints.items():check(hashlib.sha256(private_read(source/filename)).hexdigest()==digest,'original_evidence_changed')
  state.update(verified=True,commit_state='private_before_installed_after_verified',live_catalog_confirmation_by_root_required=True)
 except (Exception,KeyboardInterrupt) as error:
  if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):state['failure_code']=error.args[0]
  raise
 finally:
  target=stage/'recovery-status.json'
  with target.open('x') as handle:json.dump(state,handle,ensure_ascii=False,indent=2)
  target.chmod(0o600)
 return stage

def main():
 try:
  stage=run();result='保険料契約の既存private前後記録一致・未使用undoの別保存・外部設定読取確認: '+stage.name+'。再導入・undo実行・給与変更なし。';code=0
 except (Exception,KeyboardInterrupt):result='保険料契約の読取復旧確認は未完了です。再導入・undo実行・元marker/status変更は行っていません。';code=1
 print(result,flush=True)
 if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
 return code

if __name__=='__main__':sys.exit(main())
