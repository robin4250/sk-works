"""Pinned corrected raw-JSONB stage3 maintenance orchestration. Import/CLI never connects.

Bootstrap must provide exact private binding/approval/backup and package hashes.
No JWT fabrication, user mutation, generic SQL, retry, undo execution or gate
activation is implemented here; the separately reviewed offline plan supplies SQL.
"""
import hashlib
import importlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

PROJECT='ztktgquxvcxcjxtluspu'
IMAGE='sha256:23c24e85395992be118734a39903e08c8f7d1abc73978c46b6bda90060091a49'
STAGE1_APPROVAL='4a79fc645f3c2f7d4cfee885abcc3d9054048102d3e71cf17c21082887880a4f'
STAGE2_UNDO='07a2200f8ad0cb36dd5961044996f44bff103065ddffb85c985e0e1789303e47'
STAGE2_SOURCES={'owner_stage2.py':'8a3a403b7f8daea5420ee60987440c91515bdd64703f19c30192b0cf26e5e8ad','stage2_plan.mjs':'e90e09584983f9803ff00e28d42ca91205ec87aa1789f0578f25a110d0e149c2'}
MARKER='expense-stage3-raw-jsonb-install-attempt.json'
PRIOR_MARKER='expense-stage3-install-attempt.json'
OLD_STAGE3_SOURCES={
 'owner_stage3.py':'434505b15e6c3cb8167577359642d4da3d46acb292e331053629ea7552b59236',
 'stage3_plan.mjs':'e0fc92909160cf63e567f47b71824ec80581dca157696cbea9ac1b94d417a6e4',
 'stage2_plan_reference.mjs':'e90e09584983f9803ff00e28d42ca91205ec87aa1789f0578f25a110d0e149c2',
 'source/expense_direction_code_checkpoint.mjs':'9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f',
 'source/expense_direction_default_off_preparation.mjs':'5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8',
 'source/negotiation.sql.review-only':'f08628a18891c114c64f7551c33f1139879da3fb1439bac23c8eb54f1995507d',
 'maintenance.sql.review-only':'33e6a0988ddd6f747371f9d4a5b036995b0b798671ef64467e39678894d51572',
}
CORRECTED_PLAN_SHA='bd7e98697f9b2374e6fb1e97c0c9f06910cba3f9c4b2e22f717bd4596bcd92ea'
MAX_BYTES=16777216

def digest(raw):return hashlib.sha256(raw).hexdigest()

RUNTIME_SOURCES={'cli_psql_transport.py': '8dee8cb358afc0f2e82232ad67e4dbfd95ea9e7542941e02a2fd8b1ad0051ede', 'offline_generator.mjs': 'a66c5d219ae0e4a27a33a92975a7a85d4775094b191a940b2e737a74867247c0', 'expense_default_off_plan.mjs': '5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9', 'owner_cli_preflight.py': 'b44ba1adffb7fab6496b4b39c3cb4379f56b979577423f6582c38d62f5a0b279', 'offline_docker_generator.py': '15dee287cf280a4c99cda6d24caefe24323e61cf947334f2f9f74255af6cde52', 'review_runner.py': 'a3eb27c6c0c349b9eddd68b2124b0d581e7d64eaae6f85ae99ddb71317800aab', 'offline_docker_generator.sh': '8640e78115fc7f3f8827c710edbc603e8242a29d037b4a0eacf911b9e872471b', 'owner_install_bound_default_off.py': '0d128154ac783d5322b11ea695f339e314189e6cc52b2125883f6bf26f5d302a', 'owner_cli_source/owner_database_capture.py': '15875c927d90364f8dec1973f5fb1661dc12b9f5242aee5175203f7cb8a8702d', 'owner_cli_source/owner_expense_fresh_checkpoint.py': '85713123cf507ae38f265e0f39433091c0935e0279775d01e94c1e5a8ff48d30', 'owner_cli_source/owner_cli_database_capture.py': 'e4f206b3dab91f98295f2f2a1688a02cc74adb80d00d6262a3f3ce4cc9a300e0', 'source/expense_direction_code_checkpoint.mjs': '9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f', 'source/expense_direction_default_off_preparation.mjs': '5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8', 'source/expense_payment_direction_v2_20261019.sql.review-only': '770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a'}

def offline_docker(package, stage, mode, data=None):
    """The existing immutable local Node image; no network, pull or credentials."""
    if mode not in ('capture-sql', 'install', 'classify', 'undo') or any(k.startswith('DOCKER_') for k in os.environ):
        raise RuntimeError('offline_mode_refused')
    package, stage = Path(package), Path(stage)
    root = Path.home() / 'SKO-source-backups' / ('expense-default-off-production-' + PROJECT)
    for path in (package, stage):
        if path.parent != root or ',' in str(path) or any(p.is_symlink() for p in (path, *path.parents)):
            raise RuntimeError('offline_path_refused')
        st = path.stat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise RuntimeError('offline_private_directory_required')
    search = '/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin'
    found = shutil.which('docker', path=search)
    if not found:
        raise RuntimeError('existing_docker_required')
    docker = str(Path(found).resolve(strict=True))
    metadata = Path(docker).stat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid not in (0, os.getuid()) or metadata.st_mode & 0o022:
        raise RuntimeError('docker_binary_refused')
    env = {'HOME': pwd.getpwuid(os.getuid()).pw_dir, 'PATH': search, 'LANG': 'C', 'LC_ALL': 'C'}
    def run(args, payload=None, timeout=25):
        result = subprocess.run(args, input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=env, timeout=timeout, close_fds=True)
        if result.returncode or len(result.stdout) > 16777216:
            raise RuntimeError('offline_stage3_refused')
        return result.stdout
    context = json.loads(run([docker, 'context', 'inspect'], timeout=15))
    if len(context) != 1:
        raise RuntimeError('local_docker_required')
    endpoint = urlsplit(context[0]['Endpoints']['docker']['Host'])
    if endpoint.scheme != 'unix' or endpoint.netloc or not endpoint.path.startswith('/') or endpoint.query or endpoint.fragment:
        raise RuntimeError('local_docker_required')
    image = json.loads(run([docker, 'image', 'inspect', IMAGE], timeout=15))
    if len(image) != 1 or image[0].get('Id') != IMAGE or image[0].get('Os') != 'linux' or image[0].get('Architecture') not in ('arm64', 'amd64'):
        raise RuntimeError('existing_image_changed')
    args = [docker, 'run', '--rm', '-i', '--pull=never', '--network=none', '--log-driver=none',
            '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges', '--pids-limit=64',
            '--user', str(os.getuid()) + ':' + str(os.getgid()),
            '--mount', 'type=bind,source=' + str(package) + ',target=' + str(package) + ',readonly',
            '--mount', 'type=bind,source=' + str(stage) + ',target=' + str(stage),
            '--workdir', str(stage), '--entrypoint', 'node', IMAGE,
            str(package / 'stage3_plan.mjs'), mode]
    return run(args, json.dumps(data or {}).encode())

IDENTITY_SQL=b"""BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE postgres;SET LOCAL search_path=public;
SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';
SELECT jsonb_build_object('read_only',current_setting('transaction_read_only'),
'identity',jsonb_build_object('session_user',session_user::text,'current_user',current_user::text,
'auth_uid',auth.uid(),'jwt_claims',nullif(current_setting('request.jwt.claims',true),''),
'jwt_sub',nullif(current_setting('request.jwt.claim.sub',true),''),
'jwt_role',nullif(current_setting('request.jwt.claim.role',true),''),
'failed_backend_present',exists(select 1 from pg_stat_activity where pid=3584894)));
COMMIT;"""
SUCCESS='converted_target_verified'


def private(path):
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path,*path.parents)):
        raise RuntimeError('private_path_required')
    st=path.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&0o077:
        raise RuntimeError('private_directory_required')


def read_private(path):
    private(path.parent)
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        st=os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&0o077 or not 0<st.st_size<=MAX_BYTES:
            raise RuntimeError('private_file_required')
        raw=os.read(fd,st.st_size+1)
        if len(raw)!=st.st_size:raise RuntimeError('private_file_changed')
        return raw
    finally:os.close(fd)


def verify_files(folder,pins):
    private(folder)
    for name,expected in pins.items():
        if not isinstance(name,str) or Path(name).is_absolute() or '..' in Path(name).parts or not re.fullmatch('[0-9a-f]{64}',expected):
            raise RuntimeError('source_pin_invalid')
        if digest(read_private(folder/name))!=expected:raise RuntimeError('source_pin_differs')


def verify_transport_binding(root,runtime):
    expected=("from pathlib import Path\nAPPROVED_DURABLE_ROOT = Path("+repr(str(root))+")\nAPPROVED_MANIFEST_SHA256 = "+repr(STAGE1_APPROVAL)+"\n").encode()
    if read_private(runtime/'production_transport_binding.py')!=expected:
        raise RuntimeError('compiled_transport_binding_differs')


def verified_input(root,path,expected):
    path=Path(path)
    if not path.is_relative_to(root) or not re.fullmatch('[0-9a-f]{64}',expected):
        raise RuntimeError('private_binding_path_refused')
    raw=read_private(path)
    if digest(raw)!=expected:raise RuntimeError('private_input_hash_differs')
    return raw


def bind_identity(raw,transport,original):
    value=json.loads(raw)
    identity=value.get('identity',{})
    actual=identity.get('session_user')
    if value.get('read_only')!='on' or not isinstance(actual,str) or not re.fullmatch(r'cli_login_[A-Za-z0-9_]+(?:\.ztktgquxvcxcjxtluspu)?',actual):
        raise RuntimeError('maintenance_identity_refused')
    if identity.get('current_user')!='postgres' or set(identity)!={'session_user','current_user','auth_uid','jwt_claims','jwt_sub','jwt_role','failed_backend_present'} or any(identity[k] is not None for k in ('auth_uid','jwt_claims','jwt_sub','jwt_role')):
        raise RuntimeError('maintenance_identity_refused')
    if identity.get('failed_backend_present') is not False:raise RuntimeError('previous_backend_still_present')
    if transport.config.get('PGUSER') not in (actual,actual+'.'+PROJECT):
        raise RuntimeError('maintenance_login_binding_differs')
    result=dict(original)
    if result.get('expected_db_login') not in (None,actual):
        raise RuntimeError('private_login_binding_differs')
    result['expected_db_login']=actual
    return result


def plan(offline,package,stage,mode,data):
    raw=offline(package,stage,mode,data)
    if not isinstance(raw,bytes) or not 0<len(raw)<=MAX_BYTES:raise RuntimeError('offline_result_invalid')
    value=json.loads(raw)
    if not isinstance(value,dict):raise RuntimeError('offline_result_invalid')
    return value


def sql_result(value):
    sql=value.get('sql')
    if not isinstance(sql,str) or not 0<len(sql.encode())<=MAX_BYTES:raise RuntimeError('offline_sql_invalid')
    return sql.encode()


def execute_bound(root,package,binding,transport,offline,owner,runner,package_pins,prior_proof):
    """Internal verified-bootstrap continuation; never selects credentials itself."""
    marker=root/MARKER
    with runner.operation_lock(root):
        if marker.exists() or marker.is_symlink():raise RuntimeError('previous_stage3_attempt_requires_readonly_recovery')
        if digest(read_private(root/PRIOR_MARKER))!=prior_proof['marker_sha256']:raise RuntimeError('prior_stage3_marker_changed')
        stage=Path(tempfile.mkdtemp(prefix='expense-stage3-raw-jsonb-attempt-',dir=root))
        from review_runner import FILES
        transport.artifacts={FILES[2]:digest(IDENTITY_SQL)}
        bound=bind_identity(transport.capture_readonly(IDENTITY_SQL),transport,binding)
        owner._write_once(stage/'binding.private.json',json.dumps(bound,sort_keys=True).encode())
        read_sql=sql_result(plan(offline,package,stage,'capture-sql',{'binding':bound}))
        owner._write_once(stage/'capture.sql.read-only',read_sql)
        transport.artifacts={FILES[2]:digest(read_sql)}
        before_raw=transport.capture_readonly(read_sql)
        owner._write_once(stage/'before.private.json',before_raw)
        before=json.loads(before_raw)
        # Revalidate all sources immediately before generating and submitting SQL.
        verify_files(package,package_pins)
        maintenance=read_private(package/'maintenance.sql.review-only').decode()
        request={'before':before,'maintenanceText':maintenance,'binding':bound}
        sql=sql_result(plan(offline,package,stage,'install',request))
        owner._write_once(stage/'install.sql.review-only',sql)
        verify_files(package,package_pins)
        if sql_result(plan(offline,package,stage,'install',request))!=sql:
            raise RuntimeError('stage3_plan_not_reproducible')
        transport.artifacts={FILES[1]:digest(sql),FILES[2]:digest(read_sql)}
        state={'schema':3,'project':PROJECT,'stage':str(stage),'phase':'submission_pending',
               'retry_allowed':False,'commit_acknowledged':False,'install_sha256':digest(sql),
               'read_sql_sha256':digest(read_sql),'before_sha256':digest(before_raw),
               'bound_binding_sha256':digest(read_private(stage/'binding.private.json')),
               'authorization_reference':bound['authorization_reference'],
               'previous_stage3_marker_sha256':prior_proof['marker_sha256'],
               'previous_install_sha256':prior_proof['install_sha256'],
               'corrected_plan_sha256':CORRECTED_PLAN_SHA}
        # Exclusive creation plus fsync precedes the only mutation submission.
        # A crash from this point permanently blocks run(), even if no SQL was sent.
        if marker.exists() or marker.is_symlink():raise RuntimeError('previous_stage3_attempt_requires_readonly_recovery')
        runner.write_new(marker,json.dumps(state,sort_keys=True).encode())
        try:
            transport.execute_install_once(sql)
            state.update(phase='commit_acknowledged',commit_acknowledged=True)
        except (Exception,KeyboardInterrupt):
            state['phase']='commit_unknown'
        runner.atomic_state(marker,state)
        try:
            after_raw=transport.capture_readonly(read_sql)
            owner._write_once(stage/'after.private.json',after_raw)
            classification=plan(offline,package,stage,'classify',{'before':before,'after':json.loads(after_raw),'binding':bound})
            if classification.get('retry_allowed') is not False or classification.get('state') not in (SUCCESS,'before_state_observed','state_requires_review'):
                raise RuntimeError('classification_refused')
            state['phase']=classification['state']
            state['after_sha256']=digest(after_raw)
        except (Exception,KeyboardInterrupt):
            state['phase']='state_requires_review'
        # No unused undo is valid after a financial conversion. No undo executes.
        runner.atomic_state(marker,state)
        return {'schema':3,'project':PROJECT,'phase':state['phase'],
                'commit_acknowledged':state['commit_acknowledged'],'retry_allowed':False,
                'conversion_verified':state['phase']==SUCCESS,'complete':False}


def verify_previous(root,offline):
    """Read-only old evidence verification; never clears, edits or submits old SQL."""
    old_package=root/'stage3-runtime'
    verify_files(old_package,OLD_STAGE3_SOURCES)
    marker_raw=read_private(root/PRIOR_MARKER)
    marker=json.loads(marker_raw)
    if marker.get('schema')!=3 or marker.get('project')!=PROJECT or marker.get('phase')!='before_state_observed' or marker.get('commit_acknowledged') is not False or marker.get('retry_allowed') is not False:
        raise RuntimeError('prior_stage3_receipt_not_verified')
    if 'unused_undo' in marker or 'unused_undo_sha256' in marker:raise RuntimeError('prior_stage3_undo_unexpected')
    stage=Path(marker['stage'])
    if stage.parent!=root or not stage.name.startswith('expense-stage3-attempt-'):
        raise RuntimeError('prior_stage3_stage_refused')
    records={}
    for filename,key in {'before.private.json':'before_sha256','after.private.json':'after_sha256','install.sql.review-only':'install_sha256','binding.private.json':'bound_binding_sha256','capture.sql.read-only':'read_sql_sha256'}.items():
        raw=read_private(stage/filename)
        if digest(raw)!=marker.get(key):raise RuntimeError('prior_stage3_evidence_hash_differs')
        records[filename]=raw
    before=json.loads(records['before.private.json']);after=json.loads(records['after.private.json'])
    if before!=after or before.get('schema')!=3 or before.get('read_only')!='on':
        raise RuntimeError('prior_stage3_before_after_differ')
    old_binding=json.loads(records['binding.private.json'])
    if old_binding.get('authorization_reference')!=marker.get('authorization_reference'):
        raise RuntimeError('prior_stage3_authorization_differs')
    # Reproduce old SQL from its original pinned plan in a NEW private scratch
    # directory. Old evidence and source remain read-only inputs.
    temporary=Path(tempfile.mkdtemp(prefix='expense-stage3-raw-jsonb-prior-check-',dir=root))
    request={'before':before,'maintenanceText':read_private(old_package/'maintenance.sql.review-only').decode(),'binding':old_binding}
    reproduced=sql_result(plan(offline,old_package,temporary,'install',request))
    if reproduced!=records['install.sql.review-only']:
        raise RuntimeError('prior_stage3_sql_not_reproducible')
    classified=plan(offline,old_package,temporary,'classify',{'before':before,'after':after,'binding':old_binding})
    if classified!={'state':'before_state_observed','retry_allowed':False}:
        raise RuntimeError('prior_stage3_classification_differs')
    return {'marker_sha256':digest(marker_raw),'install_sha256':digest(records['install.sql.review-only'])}


def run(root,package,expected_sources,private_binding_path,private_binding_sha256,
        approval_path,approval_sha256,backup_path,backup_sha256,offline=offline_docker):
    """All paths/hashes are literal independently reviewed bootstrap bindings."""
    os.umask(0o077)
    if sys.platform!='darwin' or not sys.flags.isolated:raise RuntimeError('isolated_mac_required')
    root,package=Path(root),Path(package)
    if root!=Path.home()/'SKO-source-backups'/('expense-default-off-production-'+PROJECT) or package!=root/'stage3-raw-jsonb-runtime':
        raise RuntimeError('fixed_operator_root_required')
    private(root)
    if (root/MARKER).exists() or (root/MARKER).is_symlink():raise RuntimeError('previous_stage3_attempt_requires_readonly_recovery')
    if not {'owner_stage3.py','stage3_plan.mjs','stage2_plan_reference.mjs','source/expense_direction_code_checkpoint.mjs','source/expense_direction_default_off_preparation.mjs','source/negotiation.sql.review-only','maintenance.sql.review-only'}.issubset(expected_sources):
        raise RuntimeError('complete_stage3_pins_required')
    if expected_sources.get('stage3_plan.mjs')!=CORRECTED_PLAN_SHA:raise RuntimeError('corrected_plan_pin_required')
    verify_files(package,expected_sources)
    prior_proof=verify_previous(root,offline)
    runtime=root/'runtime';verify_files(runtime,RUNTIME_SOURCES)
    verify_files(root/'stage2-runtime',STAGE2_SOURCES)
    if digest(read_private(root/'production-approval.json'))!=STAGE1_APPROVAL:raise RuntimeError('stage1_approval_differs')
    stage2=json.loads(read_private(root/'expense-stage2-install-attempt.json'))
    if stage2.get('phase')!='installed_off_unused_undo_candidate' or stage2.get('commit_acknowledged') is not True or stage2.get('unused_undo_sha256')!=STAGE2_UNDO:
        raise RuntimeError('verified_stage2_required')
    prior_stage=Path(stage2['stage'])
    if prior_stage.parent!=root or not prior_stage.name.startswith('expense-stage2-prepare-') or digest(read_private(prior_stage/'unused-undo.sql.review-only'))!=STAGE2_UNDO:
        raise RuntimeError('stage2_evidence_differs')
    raw_binding=verified_input(root,private_binding_path,private_binding_sha256)
    verified_input(root,approval_path,approval_sha256)
    verified_input(root,backup_path,backup_sha256)
    binding=json.loads(raw_binding)
    if binding.get('project')!=PROJECT or binding.get('schema')!=3 or binding.get('authorization_reference')!=approval_sha256:
        raise RuntimeError('authorization_binding_differs')
    verify_transport_binding(root,runtime)
    if any(name in sys.modules for name in ('cli_psql_transport','production_transport_binding','review_runner','owner_install_bound_default_off','owner_cli_preflight')):
        raise RuntimeError('operator_module_already_loaded')
    sys.path.insert(0,str(runtime))
    owner=importlib.import_module('owner_install_bound_default_off')
    module=importlib.import_module('cli_psql_transport')
    runner=importlib.import_module('review_runner')
    approved=module._approved_binding()
    transport=module._operator_transport(approved)
    return execute_bound(root,package,binding,transport,offline,owner,runner,expected_sources,prior_proof)


def copy_result(result):
    raw=json.dumps(result,ensure_ascii=False,sort_keys=True)
    print(raw,flush=True)
    subprocess.run(['/usr/bin/pbcopy'],input=raw,text=True,check=True,timeout=10)


if __name__=='__main__':
    print('hash_pinned_stage3_bootstrap_required')
    raise SystemExit(2)
