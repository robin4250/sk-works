"""Read-only, bounded checkpoint-record summary; never validates an app/install."""
import json
import os
from pathlib import PurePosixPath
import re
import stat

ROOT = '/Users/ryuichi/SKO-source-backups'
MAX_BYTES = 1024 * 1024
PHASES = set('startup tool_preflight source_snapshot native_snapshot previous_signature git_backup isolated_checkout native_link_plan dependency_checkpoint native_signing_copy local_environment prepare_native prepared_link_plan native_contract release_build compiled_settings built_link_plan release_payload new_signature preservation_verification install_preflight owner_install'.split())
KINDS = set('RuntimeError CalledProcessError FileNotFoundError PermissionError TimeoutExpired ValueError KeyError OSError CheckedFailure OtherError'.split())
CATEGORIES = set('mac_required flutter_version xcode_version bundle_mismatch callback_configuration signature_identity local_environment_missing copy_verification source_changed original_changed owner_device_missing check_failed operation_failed'.split())
NOTICE = '※保存記録のみです。終了コード・現在の稼働・インストール完了は未確認です。'


def open_directory(root):
    path = PurePosixPath(root)
    if not path.is_absolute() or '..' in path.parts or '\x00' in str(root):
        raise ValueError('unsafe path')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open('/', flags)
    try:
        for part in path.parts[1:]:
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except Exception:
        os.close(fd)
        raise


def record(directory, name):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    except FileNotFoundError:
        return 'absent', None
    except Exception:
        return 'unknown', None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES or info.st_nlink != 1:
            return 'unknown', None
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            return 'unknown', None
        value = json.loads(data)
        return ('present', value) if isinstance(value, dict) else ('unknown', None)
    except Exception:
        return 'unknown', None
    finally:
        os.close(fd)


def built_summary(state, value, expected_source):
    if state != 'present':
        return ('完了検証記録なし' if state == 'absent' else '完了検証記録不明'), '不明'
    sha = value.get('sha')
    sha = sha.lower() if isinstance(sha, str) and re.fullmatch(r'[0-9a-fA-F]{40}', sha) else '不明'
    proof = value.get('release_settings_proof')
    root = value.get('root')
    valid_root = isinstance(root, str) and root.startswith('/') and '..' not in PurePosixPath(root).parts and '\x00' not in root
    valid = value.get('checkpoint_schema') == 2 and type(value.get('checkpoint_schema')) is int and sha != '不明' and valid_root and value.get('source') == expected_source and isinstance(proof, dict) and proof.get('CONFIGURATION') == 'Release' and proof.get('FLUTTER_BUILD_MODE', 'release') == 'release' and proof.get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.skworks.skWorks' and value.get('release_command') == ['flutter', 'build', 'ios', '--release', '--dart-define=SKO_MASTER_PASSWORD_V1=false'] and value.get('owner_only') is True and value.get('testflight_approved') is False and isinstance(value.get('dependency_checkpoint_sha256'), str) and re.fullmatch(r'[0-9a-f]{64}', value['dependency_checkpoint_sha256'])
    return ('完了検証記録あり（記録のみ）' if valid else '完了検証記録不明'), sha


def failure_summary(state, value):
    if state != 'present':
        return '失敗記録なし' if state == 'absent' else '失敗記録不明'
    phase, kind, category = (value.get(key) for key in ('phase', 'kind', 'category'))
    if not all(isinstance(v, str) for v in (phase, kind, category)) or phase not in PHASES or kind not in KINDS or category not in CATEGORIES:
        return '失敗記録不明'
    return f'失敗記録 {phase}/{kind}/{category}'


def summarize(root=ROOT):
    output = []
    directory = None
    try:
        directory = open_directory(root)
        candidates = []
        with os.scandir(directory) as entries:
            for count, entry in enumerate(entries):
                if count >= 4096:
                    raise ValueError('too many entries')
                if entry.name.startswith('r31-'):
                    candidates.append((entry.stat(follow_symlinks=False).st_mtime_ns, entry.name))
        for index, (_, name) in enumerate(sorted(candidates, reverse=True)[:3], 1):
            stage = None
            try:
                if not re.fullmatch(r'r31-[a-zA-Z0-9_-]{1,80}', name):
                    raise ValueError('unsafe checkpoint')
                stage = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
                built, sha = built_summary(*record(stage, 'built-private.json'), str(PurePosixPath(root) / name / 'source'))
                failure = failure_summary(*record(stage, 'failure-private.json'))
                output.append(f'最新{index}: {built} / {failure} / SHA={sha}')
            except Exception:
                output.append(f'最新{index}: 不明（安全に読取不可） / SHA=不明')
            finally:
                if stage is not None:
                    os.close(stage)
        if not candidates:
            output.append('記録なし（前回の結果は不明）')
    except Exception:
        output = ['不明（保存先を安全に確認できません）']
    finally:
        if directory is not None:
            os.close(directory)
    return output + [NOTICE]


if __name__ == '__main__':
    print('\n'.join(summarize()))
