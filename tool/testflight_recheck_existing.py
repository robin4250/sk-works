#!/usr/bin/env python3
"""Reverify one preserved TestFlight IPA. Never builds, installs or uploads."""
import argparse
import ast
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

R31_HASH = '3f0c33ece0f6c0f7c1b1b24caa448c916828fbd6df66b66c7278fe3f0c93dd09'


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def load_module(path, name, expected_hash):
    require(path.is_file() and not path.is_symlink()
            and hashlib.sha256(path.read_bytes()).hexdigest() == expected_hash,
            'Reviewed verification helper differs')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def record(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size < 32*1024*1024,
            'Checkpoint record unavailable')
    return json.loads(path.read_text())


def check_original(stage, root, r31, log):
    require(r31.source_state(r31.Runner(root, log)) == record(stage/'original-private.json'),
            'Original checkout changed; never restore automatically')
    require(r31.inventory(root/'ios') == r31.inventory(stage/'original-ios'),
            'Original native files changed')
    for name in ('archive', 'ipa', 'iphoneos'):
        saved = stage/('previous-'+name)
        if saved.exists():
            require(r31.inventory(root/'build/ios'/name) == r31.inventory(saved),
                    'Original artifacts changed')
    for origin, saved in record(stage/'dependencies-before-private.json').items():
        require(r31.inventory(Path(origin)) == saved['inventory'],
                'Original package dependency changed')


def recheck(stage, root, sha, number, p, r31):
    require(sys.platform == 'darwin', 'Mac required')
    require(re.fullmatch('[0-9a-f]{40}', sha) and re.fullmatch('[1-9][0-9]*', number),
            'Explicit source SHA and build required')
    require(stage.is_dir() and not any(x.is_symlink() for x in (stage, *stage.parents)),
            'Unsafe checkpoint')
    start = record(stage/'started-private.json')
    require(start.get('sha') == sha and start.get('build_number') == number,
            'Checkpoint source differs')
    require(record(stage/'failed-private.json').get('phase') == 'candidate_build'
            and not (stage/'complete-private.json').exists(), 'Not the preserved failed candidate')
    source = stage/'source'
    ipas = list((source/'build/ios/ipa').glob('*.ipa'))
    require(len(ipas) == 1 and ipas[0].is_file() and not ipas[0].is_symlink(),
            'Exactly one existing IPA required')
    marker = source/'build/ios/sko-testflight-build-start.json'
    marker_data = record(marker)
    require(marker_data.get('commit') == sha and marker_data.get('branch') == 'main',
            'Original build marker differs')
    before = p.digest(ipas[0])
    manifest = source/'build/ios/sko-testflight-provenance-rechecked.json'
    receipt = stage/'reverified-private.json'
    require(not manifest.exists() and not receipt.exists(), 'Reverification already attempted; inspect saved result')
    lock_path = stage.parent/'testflight-candidate.lock'
    fd = os.open(lock_path, os.O_RDWR | os.O_NOFOLLOW)
    with os.fdopen(fd, 'r+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with (stage/'reverification-private.log').open('ab') as log:
            check_original(stage, root, r31, log)
            runner = r31.Runner(source, log)
            runner.git('fetch', '--no-tags', '--no-write-fetch-head', 'origin',
                       '+refs/heads/main:refs/remotes/origin/main')
            old = Path.cwd()
            os.environ['SKO_AUDITED_SHA'] = sha
            try:
                os.chdir(source)
                p.create(ipas[0], marker, manifest, '0.2.0', number)
                require(p.validate(manifest) == ipas[0], 'Verified IPA path differs')
            finally:
                os.chdir(old)
            require(p.digest(ipas[0]) == before, 'Existing IPA changed')
            check_original(stage, root, r31, log)
            r31.write_private(receipt, {'schema': 1, 'sha': sha, 'build_number': number,
                'ipa_sha256': before, 'manifest': str(manifest),
                'verification_helper_sha256': hashlib.sha256(Path(p.__file__).read_bytes()).hexdigest(),
                'original_failure_preserved': True, 'rebuilt': False, 'uploaded': False, 'installed': False})
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--approved-sha', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--verifier-sha256', required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        source = args.checkpoint/'source'
        p = load_module(Path(__file__).with_name('testflight_provenance.py'), 'reviewed_provenance', args.verifier_sha256)
        r31 = load_module(source/'tool/r31_local_release.py', 'reviewed_r31', R31_HASH)
        recheck(args.checkpoint, Path('/Users/ryuichi/Desktop/sk-works'), args.approved_sha, args.build, p, r31)
        message = '今回の既存IPAの再検証が完了しました。再ビルド・アップロード・インストールはしていません。'
        code = 0
    except Exception as error:
        # Only reviewed static verification reasons may leave the private log boundary.
        safe = {'Reviewed verification helper differs', 'Checkpoint record unavailable',
                'Original checkout changed; never restore automatically', 'Original native files changed',
                'Original artifacts changed', 'Original package dependency changed',
                'Checkpoint source differs', 'Not the preserved failed candidate',
                'Exactly one existing IPA required', 'Original build marker differs',
                'Reverification already attempted; inspect saved result'}
        if 'p' in locals():
            for node in ast.walk(ast.parse(Path(p.__file__).read_text())):
                if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                        and node.func.id == 'require' and len(node.args) > 1
                        and isinstance(node.args[1], ast.Constant)
                        and isinstance(node.args[1].value, str)):
                    safe.add(node.args[1].value)
        safe.update('Required local verification command failed: '+command
                    for command in ('git', 'flutter', 'xcodebuild', 'gh',
                                    '/usr/bin/codesign', '/usr/bin/security'))
        reason = str(error) if str(error) in safe else type(error).__name__
        message = '再検証を停止しました。既存IPAは保持し、再作成していません。確認区分: '+reason
        code = 1
    message += chr(10)+'終了コード: '+str(code)
    print(message, flush=True)
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/pbcopy'], input=message.encode(), check=False)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
