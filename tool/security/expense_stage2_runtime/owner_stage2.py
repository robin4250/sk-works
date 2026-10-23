"""Owner-only supplemental expense preparation; gates and financial rows stay OFF.

This file is a review candidate. No CLI invocation or connection occurs at import.
The bootstrap must pin this file, the offline plan and its immutable SQL sources.
"""
import hashlib
import importlib
import json
import os
from pathlib import Path
import stat
import pwd
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

PROJECT = 'ztktgquxvcxcjxtluspu'
STAGE1_APPROVAL = '4a79fc645f3c2f7d4cfee885abcc3d9054048102d3e71cf17c21082887880a4f'
STAGE1_UNDO = 'f0ce855aa4f88386b84bcadcec1bfdb93e94d215d79684127b95cef25341e437'
IMAGE = 'sha256:23c24e85395992be118734a39903e08c8f7d1abc73978c46b6bda90060091a49'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


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
            raise RuntimeError('offline_stage2_refused')
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
            str(package / 'stage2_plan.mjs'), mode]
    return run(args, json.dumps(data or {}).encode())


def prepare(root, package, offline, expected_sources, runtime_sources):
    """Capture fresh state and prepare review files, without executing install SQL."""
    os.umask(0o077)
    if sys.platform != 'darwin' or not sys.flags.isolated:
        raise RuntimeError('isolated_mac_required')
    expected_root = Path.home() / 'SKO-source-backups' / ('expense-default-off-production-' + PROJECT)
    root, package = Path(root), Path(package)
    if root != expected_root:
        raise RuntimeError('fixed_root_required')
    # The previous owner helper is already independently hash-pinned by bootstrap.
    runtime = root / 'runtime'
    for name, expected_hash in runtime_sources.items():
        path = runtime / name
        if not path.is_absolute() or any(p.is_symlink() for p in (path, *path.parents)):
            raise RuntimeError('runtime_path_refused')
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or st.st_size > 16777216:
                raise RuntimeError('runtime_file_refused')
            if digest(os.read(fd, st.st_size + 1)) != expected_hash:
                raise RuntimeError('runtime_source_changed')
        finally:
            os.close(fd)
    if not {'owner_install_bound_default_off.py', 'cli_psql_transport.py', 'review_runner.py', 'owner_cli_preflight.py'}.issubset(runtime_sources):
        raise RuntimeError('complete_runtime_pins_required')
    binding_path = runtime / 'production_transport_binding.py'
    expected_binding = ('from pathlib import Path\nAPPROVED_DURABLE_ROOT = Path(' + repr(str(root)) +
                        ')\nAPPROVED_MANIFEST_SHA256 = ' + repr(STAGE1_APPROVAL) + '\n').encode()
    if binding_path.is_symlink() or binding_path.read_bytes() != expected_binding:
        raise RuntimeError('stage1_binding_changed')
    marker2 = root / 'expense-stage2-install-attempt.json'
    if marker2.exists() or marker2.is_symlink():
        raise RuntimeError('previous_stage2_attempt_requires_readonly_recovery')
    sys.path.insert(0, str(runtime))
    owner = importlib.import_module('owner_install_bound_default_off')
    owner._private_directory(root)
    owner._private_directory(runtime)
    owner._private_directory(package)
    for name, expected_hash in expected_sources.items():
        if digest(owner._read(package / name)) != expected_hash:
            raise RuntimeError('stage2_source_changed')
    if digest(owner._read(root / 'production-approval.json')) != STAGE1_APPROVAL:
        raise RuntimeError('stage1_approval_changed')
    marker = json.loads(owner._read(root / owner.MARKER))
    if marker.get('phase') != 'installed_off_unused_undo_candidate' or marker.get('commit_acknowledged') is not True:
        raise RuntimeError('verified_stage1_required')
    if marker.get('unused_undo_sha256') != STAGE1_UNDO:
        raise RuntimeError('stage1_undo_changed')
    undo = Path(marker['unused_undo'])
    if undo.parent.parent != root or digest(owner._read(undo)) != STAGE1_UNDO:
        raise RuntimeError('stage1_evidence_changed')
    transport_module = importlib.import_module('cli_psql_transport')
    binding = transport_module._approved_binding()
    # Offline plan validation and SQL generation precede any CLI credential use.
    stage = Path(tempfile.mkdtemp(prefix='expense-stage2-prepare-', dir=root))
    raw_query = json.loads(offline(package, stage, 'capture-sql'))['sql'].encode()
    if not 0 < len(raw_query) <= 1048576:
        raise RuntimeError('capture_query_invalid')
    owner._write_once(stage / 'capture.sql.read-only', raw_query)
    transport = transport_module._operator_transport(binding)
    # The reviewed transport requires a literal hash for every submitted byte.
    # This preparation path exposes only capture_readonly, never install.
    from review_runner import FILES
    transport.artifacts = {FILES[2]: digest(raw_query)}
    raw_before = transport.capture_readonly(raw_query)
    owner._write_once(stage / 'before.private.json', raw_before)
    before = json.loads(raw_before)
    converter = owner._read(package / 'source' / 'converter.sql.review-only').decode()
    negotiation = owner._read(package / 'source' / 'negotiation.sql.review-only').decode()
    raw_install = json.loads(offline(package, stage, 'install', {
        'before': before, 'converterText': converter, 'negotiationText': negotiation,
    }))['sql'].encode()
    owner._write_once(stage / 'install.sql.review-only', raw_install)
    return {'schema': 1, 'project': PROJECT, 'phase': 'supplemental_prepared',
            'application_data_mutations': False, 'deployment_performed': False,
            'conversion_performed': False, 'complete': False,
            'cli_temporary_role_requested': True, 'stage': stage.name,
            'install_sha256': digest(raw_install)}


def copy_result(result):
    """Only sanitized receipt fields reach stdout or clipboard."""
    raw = json.dumps(result, ensure_ascii=False, sort_keys=True)
    print(raw, flush=True)
    subprocess.run(['/usr/bin/pbcopy'], input=raw, text=True, check=True, timeout=10)


def install_prepared(root, package, stage, offline, expected_install_sha256):
    """One submission only. Every outcome requires a fresh read; never retries."""
    root, package, stage = Path(root), Path(package), Path(stage)
    owner = importlib.import_module('owner_install_bound_default_off')
    module = importlib.import_module('cli_psql_transport')
    runner = importlib.import_module('review_runner')
    if root != Path.home() / 'SKO-source-backups' / ('expense-default-off-production-' + PROJECT):
        raise RuntimeError('fixed_root_required')
    if stage.parent != root or not stage.name.startswith('expense-stage2-prepare-'):
        raise RuntimeError('fixed_stage_required')
    owner._private_directory(stage)
    marker = root / 'expense-stage2-install-attempt.json'
    with runner.operation_lock(root):
        if marker.exists() or marker.is_symlink():
            raise RuntimeError('previous_stage2_attempt_requires_readonly_recovery')
        before = json.loads(owner._read(stage / 'before.private.json'))
        sql = owner._read(stage / 'install.sql.review-only')
        if digest(sql) != expected_install_sha256:
            raise RuntimeError('approved_stage2_sql_changed')
        # Reproduce the plan immediately before submission, from immutable inputs.
        request = {'before': before,
                   'converterText': owner._read(package / 'source' / 'converter.sql.review-only').decode(),
                   'negotiationText': owner._read(package / 'source' / 'negotiation.sql.review-only').decode()}
        if json.loads(offline(package, stage, 'install', request))['sql'].encode() != sql:
            raise RuntimeError('stage2_plan_not_reproducible')
        read_sql = json.loads(offline(package, stage, 'capture-sql'))['sql'].encode()
        binding = module._approved_binding()
        transport = module._operator_transport(binding)
        transport.artifacts = {runner.FILES[1]: digest(sql), runner.FILES[2]: digest(read_sql)}
        state = {'schema': 1, 'phase': 'submission_pending', 'retry_allowed': False,
                 'commit_acknowledged': False, 'install_sha256': digest(sql), 'stage': str(stage)}
        owner._write_once(marker, json.dumps(state, sort_keys=True).encode())
        try:
            transport.execute_install_once(sql)
            state.update(phase='commit_acknowledged', commit_acknowledged=True)
        except (Exception, KeyboardInterrupt):
            state['phase'] = 'commit_unknown'
        runner.atomic_state(marker, state)
        try:
            after_raw = transport.capture_readonly(read_sql)
            owner._write_once(stage / 'after.private.json', after_raw)
            request = {'before': before, 'after': json.loads(after_raw)}
            classification = json.loads(offline(package, stage, 'classify', request))
            state['phase'] = classification['state']
            if state['phase'] == 'installed_off_unused_undo_candidate':
                undo = json.loads(offline(package, stage, 'undo', request))['sql'].encode()
                owner._write_once(stage / 'unused-undo.sql.review-only', undo)
                state['unused_undo_sha256'] = digest(undo)
        except (Exception, KeyboardInterrupt):
            state['phase'] = 'state_requires_review'
        runner.atomic_state(marker, state)
        return {'schema': 1, 'project': PROJECT, 'phase': state['phase'],
                'commit_acknowledged': state['commit_acknowledged'],
                'deployment_performed': True if state['phase'] == 'installed_off_unused_undo_candidate' else None,
                'application_data_mutations': False, 'conversion_performed': False,
                'retry_allowed': False, 'complete': False,
                'unused_undo_sha256': state.get('unused_undo_sha256')}


if __name__ == '__main__':
    print('hash_pinned_stage2_bootstrap_required')
    raise SystemExit(2)
