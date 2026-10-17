#!/usr/bin/env python3
"""Private owner-only Release build/checkpoint, then explicit separate install.
Not a TestFlight approval or upload tool. No database or account operations.
Unresolved production RLS/LINE controls must still block wider distribution.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile

BUNDLE = 'com.skworks.skWorks'
DEVICE = '00008110-00120536010A801E'
OFF = '--dart-define=SKO_MASTER_PASSWORD_V1=false'

def require(value, message):
    if not value:
        raise RuntimeError(message)

def inventory(root):
    """Never traverse a symlink, including generated plugin directory loops."""
    root = Path(root)
    require(root.is_dir() and not root.is_symlink(), 'unsafe inventory root')
    result = {}
    for parent, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                value = ['link', os.readlink(path)]
            elif stat.S_ISDIR(mode):
                value = ['dir']
            elif stat.S_ISREG(mode):
                h = hashlib.sha256()
                with path.open('rb') as f:
                    for block in iter(lambda: f.read(1048576), b''):
                        h.update(block)
                value = ['file', h.hexdigest()]
            else:
                raise RuntimeError('unsupported native file type')
            result[str(path.relative_to(root))] = value
    require(result, 'empty inventory')
    return result

def digest(root):
    return hashlib.sha256(json.dumps(inventory(root), sort_keys=True).encode()).hexdigest()

def copy_checked(source, target):
    before = inventory(source)
    shutil.copytree(source, target, symlinks=True, copy_function=shutil.copy2)
    require(inventory(target) == before == inventory(source), 'copy changed')
    return before

def isolate_native_links(original_ios, isolated_ios):
    """Rebase only links inside the saved native tree; unknown external links stop."""
    original_ios, isolated_ios = Path(original_ios).absolute(), Path(isolated_ios).absolute()
    links = [(name, value[1]) for name, value in inventory(isolated_ios).items() if value[0] == 'link']
    for name, target in links:
        source_link = original_ios / name
        # Lexical normalization intentionally does not follow cyclic symlinks.
        absolute = Path(os.path.abspath(os.path.join(source_link.parent, target)))
        require(absolute.is_relative_to(original_ios),
                'external native symlink requires explicit reviewed copy plan')
        relative = absolute.relative_to(original_ios)
        link = isolated_ios / name
        link.unlink()
        link.symlink_to(os.path.relpath(isolated_ios / relative, link.parent))

class Runner:
    def __init__(self, cwd, log):
        self.cwd, self.log = Path(cwd), log
    def run(self, args, capture=False):
        p = subprocess.run(args, cwd=self.cwd, check=True,
                           stdout=subprocess.PIPE if capture else self.log,
                           stderr=self.log)
        return p.stdout if capture else None
    def git(self, *args):
        return self.run(['git', *args], True)

def source_state(runner):
    """Private only: preserve index, dirty patches, and untracked bytes."""
    names = runner.git('ls-files', '--others', '--exclude-standard', '-z').split(b'\0')
    untracked = {}
    for raw in names:
        if not raw:
            continue
        name = os.fsdecode(raw)
        p = runner.cwd / name
        if p.is_symlink():
            untracked[name] = ['link', os.readlink(p)]
        else:
            require(p.is_file(), 'unsupported untracked item')
            untracked[name] = ['file', hashlib.sha256(p.read_bytes()).hexdigest()]
    return {'head': runner.git('rev-parse', 'HEAD').decode().strip(),
            'status': runner.git('status', '--porcelain=v1', '-z', '--untracked-files=all').hex(),
            'index': runner.git('ls-files', '--stage', '-z').hex(),
            'staged': runner.git('diff', '--cached', '--binary').hex(),
            'unstaged': runner.git('diff', '--binary').hex(), 'untracked': untracked}

def signing_settings(runner):
    p = runner.cwd / 'ios/Runner.xcodeproj/project.pbxproj'
    require(p.is_file() and not p.is_symlink(), 'native project missing')
    objects = json.loads(runner.run(['plutil', '-convert', 'json', '-o', '-', str(p)], True))['objects']
    values = {}
    for key, value in objects.items():
        if value.get('isa') == 'XCBuildConfiguration':
            b = value.get('buildSettings', {})
            values[key] = {k: v for k, v in b.items() if k.startswith(('CODE_SIGN', 'PROVISIONING'))
                           or k in ('DEVELOPMENT_TEAM', 'PRODUCT_BUNDLE_IDENTIFIER')}
    require(values, 'signing settings missing')
    return values

def signature(runner, app):
    require(app.is_dir() and not app.is_symlink(), 'app missing')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == BUNDLE, 'wrong bundle')
    require(info.get('FlutterDeepLinkingEnabled') is False, 'callback handling changed')
    require(any('com.skworks.sko' in t.get('CFBundleURLSchemes', [])
                for t in info.get('CFBundleURLTypes', [])), 'callback scheme missing')
    runner.run(['codesign', '--verify', '--deep', '--strict', str(app)])
    ent = plistlib.loads(runner.run(['codesign', '-d', '--entitlements', ':-', str(app)], True))
    team = ent.get('com.apple.developer.team-identifier')
    require(isinstance(team, str) and team, 'signed team missing')
    require(ent.get('application-identifier') == team + '.' + BUNDLE, 'signed identity mismatch')
    groups = ent.get('keychain-access-groups', [])
    require(isinstance(groups, list) and all(isinstance(x, str) for x in groups), 'invalid keychain groups')
    # Personal-device Release can use development provisioning; that is NOT Debug proof.
    return {'team': team, 'application': ent['application-identifier'], 'keychain': sorted(groups)}

def write_private(path, value):
    with Path(path).open('x') as f:
        json.dump(value, f, sort_keys=True)
    Path(path).chmod(0o600)

def tools_ready(runner):
    require(sys.platform == 'darwin', 'Mac required')
    v = json.loads(runner.run(['flutter', '--version', '--machine'], True))
    require(v.get('frameworkVersion') == '3.47.5', 'Flutter mismatch')
    require(re.search(r'^Xcode 27\.1$', runner.run(['xcodebuild', '-version'], True).decode(), re.M),
            'Xcode mismatch')

def verify_clean(runner, sha):
    require(runner.git('rev-parse', 'HEAD').decode().strip() == sha, 'source SHA changed')
    require(not runner.git('status', '--porcelain', '--untracked-files=all'), 'build source changed')

def release_command():
    # Source only the original local public-client environment; never copy it or print it.
    return ['bash', '-c', 'set -euo pipefail; set +x; source "$1" >/dev/null 2>&1; set +x; '
            'test -n "${SUPABASE_URL:-}"; test -n "${SUPABASE_PUBLISHABLE_KEY:-}"; '
            'flutter build ios --release --dart-define=SKO_MASTER_PASSWORD_V1=false '
            '--dart-define="SUPABASE_URL=$SUPABASE_URL" '
            '--dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"', 'r31']

def build(root, sha, backup_root):
    require(re.fullmatch(r'[0-9a-f]{40}', sha), 'full reviewed SHA required')
    require(root.is_dir() and not root.is_symlink(), 'source root unsafe')
    backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    require(not backup_root.is_symlink(), 'backup root unsafe')
    stage = Path(tempfile.mkdtemp(prefix='r31-', dir=backup_root)).resolve()
    print('Private checkpoint: ' + str(stage), flush=True)
    with (stage / 'private.log').open('xb') as log:
        original = Runner(root, log)
        tools_ready(original)
        before = source_state(original)
        write_private(stage / 'original-private.json', before)
        # Original untracked files are backed up privately, never added to Git.
        for name in before['untracked']:
            origin = root / name
            target = stage / 'untracked-before' / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            if origin.is_symlink():
                target.symlink_to(os.readlink(origin))
            else:
                shutil.copy2(origin, target)
        native = copy_checked(root / 'ios', stage / 'original-ios')
        oldapp = root / 'build/ios/iphoneos/Runner.app'
        oldsig = signature(original, oldapp)
        olddigest = digest(oldapp)
        copy_checked(oldapp, stage / 'previous-local.app')
        original.git('bundle', 'create', str(stage / 'source-before.bundle'), 'HEAD')
        original.git('bundle', 'verify', str(stage / 'source-before.bundle'))
        # A new detached worktree only: no checkout, merge, reset, stash or clean of root.
        original.run(['git', 'fetch', '--no-tags', '--no-write-fetch-head', 'origin', sha])
        source = stage / 'source'
        original.run(['git', 'worktree', 'add', '--detach', str(source), sha])
        candidate = Runner(source, log)
        verify_clean(candidate, sha)
        copy_checked(stage / 'original-ios', source / 'ios')
        isolate_native_links(root / 'ios', source / 'ios')
        signing = signing_settings(candidate)
        require(signing == signing_settings(original), 'native signing copy incomplete')
        env = root / 'tool/local_supabase_env.sh'
        require(env.is_file() and not env.is_symlink(), 'local environment unavailable')
        candidate.run(['bash', 'tool/prepare_ios.sh'])
        require(signing_settings(candidate) == signing, 'prepare changed signing')
        candidate.run(['bash', 'tool/check_ios_generated_contract.sh'])
        candidate.run(release_command() + [str(env)])
        settings = json.loads(candidate.run(['xcodebuild', '-workspace', 'ios/Runner.xcworkspace',
            '-scheme', 'Runner', '-configuration', 'Release', '-sdk', 'iphoneos',
            '-showBuildSettings', '-json'], True))
        runner_settings = [entry['buildSettings'] for entry in settings if entry.get('target') == 'Runner']
        require(len(runner_settings) == 1, 'compiled Release settings missing')
        require(runner_settings[0].get('CONFIGURATION') == 'Release'
                and runner_settings[0].get('FLUTTER_BUILD_MODE') == 'release'
                and runner_settings[0].get('PRODUCT_BUNDLE_IDENTIFIER') == BUNDLE,
                'not a Release application')
        verify_clean(candidate, sha)
        require(signing_settings(candidate) == signing, 'build changed signing')
        app = source / 'build/ios/iphoneos/Runner.app'
        require(signature(candidate, app) == oldsig, 'new signature changed account storage identity')
        require(source_state(original) == before, 'original source changed; never restoring automatically')
        require(inventory(root / 'ios') == native and digest(oldapp) == olddigest,
                'original native artifacts changed')
        write_private(stage / 'built-private.json', {'sha': sha, 'root': str(root), 'source': str(source),
                      'app_digest': digest(app), 'signature': oldsig, 'original_native': native,
                      'original_app_digest': olddigest, 'release_command': ['flutter', 'build', 'ios', '--release', OFF],
                      'owner_only': True, 'testflight_approved': False})
    return stage

def install(stage):
    require(stage.is_dir() and not stage.is_symlink(), 'checkpoint missing')
    with (stage / 'install-private.log').open('xb') as log:
        m = json.loads((stage / 'built-private.json').read_text())
        require(m.get('release_command') == ['flutter', 'build', 'ios', '--release', OFF]
                and m.get('owner_only') is True and m.get('testflight_approved') is False,
                'not an owner Release checkpoint')
        require(re.fullmatch(r'[0-9a-f]{40}', m['sha']), 'invalid source SHA')
        root, source = Path(m['root']), Path(m['source'])
        require(source == stage / 'source', 'checkpoint source mismatch')
        runner, original = Runner(source, log), Runner(root, log)
        tools_ready(runner)
        verify_clean(runner, m['sha'])
        before = json.loads((stage / 'original-private.json').read_text())
        require(source_state(original) == before, 'original source changed')
        require(inventory(root / 'ios') == m['original_native'], 'original iOS changed')
        require(digest(root / 'build/ios/iphoneos/Runner.app') == m['original_app_digest'], 'old app changed')
        app = source / 'build/ios/iphoneos/Runner.app'
        require(digest(app) == m['app_digest'] and signature(runner, app) == m['signature'], 'artifact changed')
        devices = json.loads(runner.run(['flutter', 'devices', '--machine'], True))
        selected = [d for d in devices if d.get('id') == DEVICE and d.get('targetPlatform') == 'ios'
                    and d.get('emulator') is False and d.get('isSupported') is True]
        require(len(selected) == 1, 'expected physical supported device missing')
        runner.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', DEVICE, str(app)])
        runner.run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', DEVICE, BUNDLE])
        require(source_state(original) == before, 'original source changed during install')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--reviewed-sha')
    mode.add_argument('--install-checkpoint', type=Path)
    parser.add_argument('--root', type=Path, default=Path('/Users/ryuichi/Desktop/sk-works'))
    parser.add_argument('--backup-root', type=Path, default=Path('/Users/ryuichi/SKO-source-backups'))
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.reviewed_sha:
            stage = build(args.root, args.reviewed_sha, args.backup_root)
            print('Owner Release build verified; NOT installed; private checkpoint: ' + str(stage))
        else:
            install(args.install_checkpoint)
            print('Owner Release overwrite install/launch complete; actual login/data/roles remain to test. NOT TestFlight approval.')
    except Exception as error:
        print('STOP: ' + type(error).__name__ + '; private checkpoints retained; no reset/deletion/automatic restoration.')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
