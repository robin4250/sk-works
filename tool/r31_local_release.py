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

_PHASE = 'startup'
_STAGE = None
SAFE_FAILURES = {
    'Mac required': 'mac_required',
    'Flutter mismatch': 'flutter_version',
    'Xcode mismatch': 'xcode_version',
    'wrong bundle': 'bundle_mismatch',
    'callback handling changed': 'callback_configuration',
    'callback scheme missing': 'callback_configuration',
    'signed team missing': 'signature_identity',
    'signed identity mismatch': 'signature_identity',
    'invalid keychain groups': 'signature_identity',
    'local environment unavailable': 'local_environment_missing',
    'copy changed': 'copy_verification',
    'source SHA changed': 'source_changed',
    'build source changed': 'source_changed',
    'new signature changed account storage identity': 'signature_identity',
    'original source changed; never restoring automatically': 'original_changed',
    'original native artifacts changed': 'original_changed',
    'expected physical supported device missing': 'owner_device_missing',
}

class CheckedFailure(RuntimeError):
    pass

def phase(name, stage=None):
    global _PHASE, _STAGE
    _PHASE = name
    if stage is not None:
        _STAGE = stage

def failure_record(error):
    kinds = {'RuntimeError', 'CalledProcessError', 'FileNotFoundError', 'PermissionError',
             'TimeoutExpired', 'ValueError', 'KeyError', 'OSError', 'CheckedFailure'}
    kind = type(error).__name__
    return {'phase': _PHASE, 'kind': kind if kind in kinds else 'OtherError',
            'category': SAFE_FAILURES.get(str(error), 'check_failed')
                        if isinstance(error, CheckedFailure) else 'operation_failed'}

def require(value, message):
    if not value:
        raise CheckedFailure(message)

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

def isolate_native_links(original_ios, isolated_ios, *, cache_root=None, dependencies=None, approved=None):
    """Copy approved generated cache dependencies; never build through original links.

    Native-internal cycles remain lexical links and are never traversed. Unknown
    external, custom cache links and nested dependency escapes fail closed.
    """
    original_ios, isolated_ios = Path(original_ios).absolute(), Path(isolated_ios).absolute()
    links = [(name, value[1]) for name, value in inventory(isolated_ios).items() if value[0] == 'link']
    replacements = []
    copied = {} if approved is None else dict(approved)
    canonical_cache = None
    for name, target in links:
        source_link = original_ios / name
        absolute = Path(os.path.abspath(os.path.join(source_link.parent, target)))
        if absolute.is_relative_to(original_ios):
            replacement = isolated_ios / absolute.relative_to(original_ios)
        elif dependencies is not None and absolute.is_relative_to(dependencies):
            canonical = absolute.resolve(strict=True)
            require(canonical in [item['destination'] for item in copied.values()],
                    'unreviewed isolated dependency link')
            replacement = canonical
        else:
            require(cache_root is not None and dependencies is not None,
                    'external native symlink requires explicit reviewed copy plan')
            cache = Path(cache_root).absolute()
            require(cache.is_dir() and not cache.is_symlink(), 'unsafe package cache root')
            if canonical_cache is None:
                canonical_cache = cache.resolve(strict=True)
                require(canonical_cache == cache, 'package cache root redirects outside expected path')
            require(name.startswith(('Flutter/ephemeral/', '.symlinks/', 'Pods/')),
                    'custom native external link is not a generated dependency')
            require(absolute.is_relative_to(cache), 'native external target outside package cache')
            # strict resolution detects missing targets, indirect escapes and loops.
            canonical = absolute.resolve(strict=True)
            require(canonical.is_relative_to(canonical_cache) and canonical != canonical_cache
                    and canonical.is_dir(), 'package dependency outside canonical cache')
            require(not dependencies.is_symlink(), 'unsafe dependency destination')
            if canonical not in copied:
                require(approved is None, 'prepare introduced an unreviewed cache dependency')
                dependencies.mkdir(mode=0o700, parents=True, exist_ok=True)
                destination = dependencies / ('dep-' + str(len(copied)))
                before = copy_checked(canonical, destination)
                require(canonical.resolve(strict=True) == canonical, 'cache path changed while copying')
                # Nested links must stay within that dependency. Do not recursively
                # authorize more cache/external paths from an unreviewed package.
                isolate_native_links(canonical, destination)
                copied[canonical] = {'destination': destination, 'inventory': before}
            replacement = copied[canonical]['destination']
        replacements.append((isolated_ios / name, replacement))
    # Do not alter even candidate links until the entire native plan validates.
    for link, replacement in replacements:
        link.unlink()
        link.symlink_to(os.path.relpath(replacement, link.parent))
    return copied


def audit_isolated_links(native, dependencies):
    # Final generated-tree audit: every link must lexically remain in private
    # native/dependency trees. Cycles remain links and are not followed.
    roots = [Path(native).absolute()]
    if Path(dependencies).exists(): roots.append(Path(dependencies).absolute())
    for root in roots:
        for name, value in inventory(root).items():
            if value[0] != 'link': continue
            target = Path(os.path.abspath(os.path.join((root / name).parent, value[1])))
            require(any(target.is_relative_to(allowed) for allowed in roots),
                    'generated link escaped isolated native plan')


def verify_release_settings(settings):
    # Flutter 3.47.5 xcode_backend.dart uses CONFIGURATION when the uncommon
    # FLUTTER_BUILD_MODE setting is absent. An explicit mode never falls back.
    require(settings.get('CONFIGURATION') == 'Release'
            and settings.get('FLUTTER_BUILD_MODE', 'release') == 'release'
            and settings.get('PRODUCT_BUNDLE_IDENTIFIER') == BUNDLE,
            'not a Release application')

def verify_aot_artifact(runner, app):
    assets = app / 'Frameworks/App.framework/flutter_assets'
    require(assets.is_dir() and not (assets / 'kernel_blob.bin').exists(),
            'debug kernel artifact present or assets missing')
    binary = app / 'Frameworks/App.framework/App'
    require(binary.is_file() and not binary.is_symlink(), 'AOT binary missing')
    symbols = runner.run(['xcrun', 'nm', '-gU', str(binary)], True).decode()
    names = {line.split()[-1] for line in symbols.splitlines() if line.split()}
    require({'_kDartVmSnapshotInstructions', '_kDartIsolateSnapshotInstructions'} <= names,
            'AOT snapshot instructions missing')

def save_dependency_checkpoint(stage, copies):
    write_private(stage / 'dependencies-before-private.json',
                  {str(origin): {'destination': str(item['destination'].relative_to(stage)),
                                 'inventory': item['inventory']}
                   for origin, item in copies.items()})

def rebase_built_links(source, stage, copies):
    # A build may regenerate plugin links back to the same package cache.
    # Re-authorize no new origin: compare every original byte/link first.
    require(all(inventory(origin) == item['inventory'] for origin, item in copies.items()),
            'original package dependency changed during build')
    isolate_native_links(source / 'ios', source / 'ios',
                         cache_root=Path.home() / '.pub-cache',
                         dependencies=stage / 'native-dependencies', approved=copies)
    audit_isolated_links(source / 'ios', stage / 'native-dependencies')

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
            'test "${SUPABASE_URL:-}" = https://ztktgquxvcxcjxtluspu.supabase.co; '
            'case "${SUPABASE_PUBLISHABLE_KEY:-}" in sb_publishable_*) ;; *) exit 1;; esac; '
            'flutter build ios --release --no-pub --dart-define=SKO_MASTER_PASSWORD_V1=false '
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
        phase('tool_preflight', stage)
        tools_ready(original)
        phase('source_snapshot')
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
        phase('native_snapshot')
        native = copy_checked(root / 'ios', stage / 'original-ios')
        oldapp = root / 'build/ios/iphoneos/Runner.app'
        phase('previous_signature')
        oldsig = signature(original, oldapp)
        olddigest = digest(oldapp)
        copy_checked(oldapp, stage / 'previous-local.app')
        phase('git_backup')
        original.git('bundle', 'create', str(stage / 'source-before.bundle'), 'HEAD')
        original.git('bundle', 'verify', str(stage / 'source-before.bundle'))
        # A new detached worktree only: no checkout, merge, reset, stash or clean of root.
        phase('isolated_checkout')
        original.run(['git', 'fetch', '--no-tags', '--no-write-fetch-head', 'origin', sha])
        source = stage / 'source'
        original.run(['git', '-c', 'core.hooksPath=/dev/null', 'worktree', 'add', '--detach', str(source), sha])
        candidate = Runner(source, log)
        verify_clean(candidate, sha)
        copy_checked(stage / 'original-ios', source / 'ios')
        phase('native_link_plan')
        copies = isolate_native_links(root / 'ios', source / 'ios',
                             cache_root=Path.home() / '.pub-cache',
                             dependencies=stage / 'native-dependencies')
        phase('dependency_checkpoint')
        save_dependency_checkpoint(stage, copies)
        phase('native_signing_copy')
        signing = signing_settings(candidate)
        require(signing == signing_settings(original), 'native signing copy incomplete')
        phase('local_environment')
        env = root / 'tool/local_supabase_env.sh'
        require(env.is_file() and not env.is_symlink(), 'local environment unavailable')
        phase('prepare_native')
        candidate.run(['bash', 'tool/prepare_ios.sh'])
        phase('prepared_link_plan')
        isolate_native_links(source / 'ios', source / 'ios',
                             cache_root=Path.home() / '.pub-cache',
                             dependencies=stage / 'native-dependencies', approved=copies)
        audit_isolated_links(source / 'ios', stage / 'native-dependencies')
        require(signing_settings(candidate) == signing, 'prepare changed signing')
        phase('native_contract')
        candidate.run(['bash', 'tool/check_ios_generated_contract.sh'])
        phase('release_build')
        candidate.run(release_command() + [str(env)])
        phase('compiled_settings')
        settings = json.loads(candidate.run(['xcodebuild', '-workspace', 'ios/Runner.xcworkspace',
            '-scheme', 'Runner', '-configuration', 'Release', '-sdk', 'iphoneos',
            '-showBuildSettings', '-json'], True))
        runner_settings = [entry['buildSettings'] for entry in settings if entry.get('target') == 'Runner']
        require(len(runner_settings) == 1, 'compiled Release settings missing')
        verify_release_settings(runner_settings[0])
        verify_clean(candidate, sha)
        phase('built_link_plan')
        rebase_built_links(source, stage, copies)
        require(all(inventory(origin) == item['inventory'] for origin, item in copies.items()),
                'original package dependency changed during build')
        require(signing_settings(candidate) == signing, 'build changed signing')
        app = source / 'build/ios/iphoneos/Runner.app'
        phase('aot_artifact')
        verify_aot_artifact(candidate, app)
        phase('new_signature')
        require(signature(candidate, app) == oldsig, 'new signature changed account storage identity')
        phase('preservation_verification')
        require(source_state(original) == before, 'original source changed; never restoring automatically')
        require(inventory(root / 'ios') == native and digest(oldapp) == olddigest,
                'original native artifacts changed')
        write_private(stage / 'built-private.json', {'checkpoint_schema': 2,
                      'dependency_checkpoint_sha256': hashlib.sha256((stage / 'dependencies-before-private.json').read_bytes()).hexdigest(), 'sha': sha, 'root': str(root), 'source': str(source),
                      'app_digest': digest(app), 'signature': oldsig, 'original_native': native,
                      'original_app_digest': olddigest, 'release_command': ['flutter', 'build', 'ios', '--release', OFF],
                      'owner_only': True, 'testflight_approved': False})
    return stage

def install(stage):
    require(stage.is_dir() and not stage.is_symlink(), 'checkpoint missing')
    with (stage / 'install-private.log').open('xb') as log:
        phase('install_preflight', stage)
        m = json.loads((stage / 'built-private.json').read_text())
        require(m.get('checkpoint_schema') == 2
                and (stage / 'dependencies-before-private.json').is_file()
                and hashlib.sha256((stage / 'dependencies-before-private.json').read_bytes()).hexdigest()
                    == m.get('dependency_checkpoint_sha256'), 'dependency checkpoint missing or changed')
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
        verify_aot_artifact(runner, app)
        require(digest(app) == m['app_digest'] and signature(runner, app) == m['signature'], 'artifact changed')
        devices = json.loads(runner.run(['flutter', 'devices', '--machine'], True))
        selected = [d for d in devices if d.get('id') == DEVICE and d.get('targetPlatform') == 'ios'
                    and d.get('emulator') is False and d.get('isSupported') is True]
        require(len(selected) == 1, 'expected physical supported device missing')
        phase('owner_install')
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
    phase('startup')
    try:
        if args.reviewed_sha:
            stage = build(args.root, args.reviewed_sha, args.backup_root)
            print('Owner Release build verified; NOT installed; private checkpoint: ' + str(stage))
        else:
            install(args.install_checkpoint)
            print('Owner Release overwrite install/launch complete; actual login/data/roles remain to test. NOT TestFlight approval.')
    except Exception as error:
        record = failure_record(error)
        if _STAGE is not None:
            try:
                write_private(_STAGE / 'failure-private.json', record)
            except Exception:
                pass  # Failure reporting never replaces the primary failure.
        print('STOP: ' + json.dumps(record, sort_keys=True) + '; private checkpoints retained; no reset/deletion/automatic restoration.')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
