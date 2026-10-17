#!/usr/bin/env python3
"""Fail-closed local release provenance. Never builds, uploads or edits source."""
import argparse
import base64
import datetime as dt
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
import zipfile

BUNDLE = 'com.skworks.skWorks'
REQUIRED_CI = {'Flutter CI', 'iOS CI', 'Secret Scan', 'TestFlight provenance'}


def require(value, reason):
    if not value:
        raise ValueError(reason)


def run(args):
    # Never echo command output on failures: tools can include account details.
    result = subprocess.run(args, capture_output=True, check=False)
    require(result.returncode == 0, 'Required local verification command failed: ' + args[0])
    return result.stdout


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def source():
    audited = os.environ.get('SKO_AUDITED_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', audited), 'Explicit reviewed SKO_AUDITED_SHA required')
    require(run(['git', 'branch', '--show-current']).decode().strip() == 'main', 'main is required')
    require(not run(['git', 'status', '--porcelain', '--untracked-files=all']).strip(),
            'Unsaved source exists; preserve changes before building or uploading')
    sha = run(['git', 'rev-parse', 'HEAD']).decode().strip()
    require(re.fullmatch('[0-9a-f]{40}', sha), 'Invalid commit')
    require(sha == audited, 'Source differs from reviewed commit')
    require(sha == run(['git', 'rev-parse', 'origin/main']).decode().strip(), 'Stale main')
    return sha


def build_context():
    """Hash only reviewed native source, never environment/keys/profiles/logs."""
    required = ['ios/Runner/Info.plist', 'ios/Runner.xcodeproj/project.pbxproj',
                'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme']
    paths = [Path(p) for p in required]
    paths += sorted(Path('ios/Runner').glob('*.entitlements'))
    native = {}
    for path in paths:
        require(path.is_file() and not path.is_symlink()
                and not any(parent.is_symlink() for parent in path.parents), 'Unsafe native source')
        native[str(path)] = digest(path)
    flutter = json.loads(run(['flutter', '--version', '--machine']))
    require(flutter.get('frameworkVersion') == '3.47.5', 'Flutter version differs')
    xcode = run(['xcodebuild', '-version']).decode().strip()
    require(re.fullmatch(r'Xcode [0-9]+(?:\.[0-9]+)*\nBuild version [A-Za-z0-9]+', xcode), 'Invalid Xcode version')
    return {'native_sha256': native,
            'flutter': {k: flutter.get(k) for k in
                        ('frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion')},
            'xcode': xcode,
            'compile_flags': {'build_mode': 'release', 'export_method': 'app-store',
                              'SKO_MASTER_PASSWORD_V1': False}}


def verify_generated_flags():
    # Decode locally for comparison only. Never retain values or their digests.
    path = Path('ios/Flutter/Generated.xcconfig')
    require(path.is_file() and not path.is_symlink()
            and not any(parent.is_symlink() for parent in path.parents), 'Unsafe generated configuration')
    lines = [line.partition('=')[2] for line in path.read_text().splitlines()
             if line.startswith('DART_DEFINES=')]
    require(len(lines) == 1, 'Generated compile flags missing')
    values = {}
    for encoded in lines[0].split(','):
        decoded = base64.b64decode(encoded, validate=True).decode()
        key, separator, value = decoded.partition('=')
        require(separator and key not in values, 'Duplicate or invalid compile define')
        values[key] = value
    require(set(values) == {'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SKO_MASTER_PASSWORD_V1'},
            'Unexpected compile defines')
    require(values['SKO_MASTER_PASSWORD_V1'] == 'false', 'Dedicated Master mode must remain off')
    require(values['SUPABASE_URL'] == 'https://ztktgquxvcxcjxtluspu.supabase.co'
            and bool(values['SUPABASE_PUBLISHABLE_KEY']), 'Approved public backend configuration required')


def check_ci(sha):
    # gh supplies its existing authentication; neither tokens nor logs are read.
    url = 'repos/robin4250/sk-works/actions/runs?head_sha=' + sha + '&per_page=100'
    data = json.loads(run(['gh', 'api', url]))
    require(data.get('total_count', 101) <= 100, 'CI results exceed the bounded response; review required')
    result = {}
    for name in REQUIRED_CI:
        runs = [r for r in data.get('workflow_runs', []) if r.get('name') == name
                and r.get('head_sha') == sha and r.get('head_branch') == 'main'
                and r.get('event') in ('push', 'workflow_dispatch')]
        require(runs, 'Missing exact-main CI: ' + name)
        latest = max(runs, key=lambda r: (r.get('run_number', 0), r.get('run_attempt', 0)))
        require(latest.get('status') == 'completed' and latest.get('conclusion') == 'success',
                'Exact-main CI is not successful: ' + name)
        result[name] = latest['id']
    return result


def inspect_ipa(ipa):
    require(sys.platform == 'darwin', 'Signature validation requires macOS')
    with tempfile.TemporaryDirectory(prefix='sko-ipa-audit-') as folder:
        root = Path(folder)
        with zipfile.ZipFile(ipa) as archive:
            names = archive.infolist()
            require(len({x.filename for x in names}) == len(names), 'Duplicate IPA entries')
            require(len(names) <= 50000 and sum(x.file_size for x in names) <= 4 * 1024**3,
                    'IPA exceeds inspection bounds')
            for item in names:
                path = Path(item.filename)
                require(not path.is_absolute() and '..' not in path.parts and '\\' not in item.filename,
                        'Unsafe IPA entry')
                require(not stat.S_ISLNK(item.external_attr >> 16), 'Symlink IPA entries are unsupported')
            archive.extractall(root)
            for item in names:
                mode = (item.external_attr >> 16) & 0o777
                if mode and not item.is_dir():
                    (root / item.filename).chmod(mode)
        apps = list((root / 'Payload').glob('*.app'))
        require(len(apps) == 1, 'Exactly one application is required')
        app = apps[0]
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == BUNDLE, 'Bundle mismatch')
        require(info.get('FlutterDeepLinkingEnabled') is False, 'Native callback handler mismatch')
        require(any('com.skworks.sko' in row.get('CFBundleURLSchemes', [])
                    for row in info.get('CFBundleURLTypes', []) if isinstance(row, dict)),
                'Existing Google callback missing')
        require((app / 'Frameworks/App.framework/App').is_file(), 'AOT executable missing')
        require(not list(app.rglob('kernel_blob.bin')), 'Debug kernel found')
        ats = info.get('NSAppTransportSecurity', {})
        require(ats.get('NSAllowsArbitraryLoads') is not True
                and ats.get('NSAllowsArbitraryLoadsInWebContent') is not True, 'Broad ATS bypass')
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)])
        ent = plistlib.loads(run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)]))
        require(ent.get('get-task-allow') is False, 'Development or missing get-task-allow')
        team = ent.get('com.apple.developer.team-identifier')
        require(isinstance(team, str) and re.fullmatch('[A-Z0-9]{10}', team), 'Signing team missing')
        app_id = ent.get('application-identifier')
        require(isinstance(app_id, str) and app_id.endswith('.' + BUNDLE), 'Signed application identifier mismatch')
        profile = plistlib.loads(run(['/usr/bin/security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
        pent = profile.get('Entitlements', {})
        require(profile.get('TeamIdentifier') == [team], 'Profile team mismatch')
        require(pent.get('application-identifier') == app_id
                and pent.get('com.apple.developer.team-identifier') == team
                and pent.get('get-task-allow') is False, 'Profile entitlement mismatch')
        require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'),
                'App Store distribution profile required')
        require(pent.get('beta-reports-active') is True, 'TestFlight distribution profile required')
        certificate_prefix = root / 'signer'
        run(['/usr/bin/codesign', '-d', '--extract-certificates', str(certificate_prefix), str(app)])
        leaf = Path(str(certificate_prefix) + '0')
        require(leaf.is_file() and leaf.read_bytes() in profile.get('DeveloperCertificates', []),
                'Signer certificate is not authorized by the profile')
        expiry = profile.get('ExpirationDate')
        require(isinstance(expiry, dt.datetime) and expiry.replace(tzinfo=dt.timezone.utc) > dt.datetime.now(dt.timezone.utc),
                'Expired or invalid provisioning profile')
        for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
            require(isinstance(info.get(key), str) and info[key], 'Version/build missing')
        return {'bundle_id': BUNDLE, 'version': info['CFBundleShortVersionString'],
                'build': info['CFBundleVersion'], 'team_id': team, 'application_identifier': app_id,
                'get_task_allow': False, 'distribution': 'app-store',
                'effective_entitlements_sha256': hashlib.sha256(plistlib.dumps(ent, sort_keys=True)).hexdigest(),
                'profile_sha256': digest(app / 'embedded.mobileprovision'),
                'native_callback': 'com.skworks.sko://login-callback/', 'flutter_deep_linking': False}


def create(ipa, marker, output, version, build):
    sha = source()
    start = json.loads(marker.read_text())
    require(start.get('commit') == sha and start.get('branch') == 'main', 'Build source changed')
    context = build_context()
    require(start.get('build_context') == context, 'Build tools/native settings changed')
    verify_generated_flags()
    require(ipa.is_file() and ipa.stat().st_mtime_ns >= start['started_ns'], 'IPA predates this build')
    before = digest(ipa)
    details = inspect_ipa(ipa)
    require(digest(ipa) == before, 'IPA changed during signature inspection')
    require(details['version'] == version and details['build'] == build, 'IPA version/build mismatch')
    ci = check_ci(sha)
    result = {'schema': 2, 'commit': sha, 'audited_commit': sha, 'branch': 'main', 'build_mode': 'release',
              'build_context': context,
              'ipa': str(ipa.resolve()), 'sha256': before, 'ci_runs': ci, **details}
    require(source() == sha, 'Source changed during verification')
    require(build_context() == context, 'Build context changed during verification')
    require(digest(ipa) == before, 'IPA changed during candidate verification')
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix('.tmp')
    temp.write_text(json.dumps(result, indent=2) + '\n')
    os.replace(temp, output)


def validate(manifest):
    sha = source()
    data = json.loads(manifest.read_text())
    require(data.get('schema') == 2 and data.get('commit') == sha and data.get('audited_commit') == sha and data.get('branch') == 'main'
            and data.get('build_mode') == 'release', 'Stale or invalid candidate manifest')
    context = build_context()
    require(data.get('build_context') == context, 'Candidate build context changed')
    verify_generated_flags()
    ipa = Path(data['ipa'])
    require(ipa.is_absolute() and ipa.is_file(), 'IPA missing')
    before = digest(ipa)
    require(before == data.get('sha256'), 'IPA modified')
    actual = inspect_ipa(ipa)
    require(digest(ipa) == before, 'IPA changed during signature inspection')
    require(all(data.get(k) == v for k, v in actual.items()), 'IPA identity changed')
    check_ci(sha)
    require(source() == sha, 'Source changed during verification')
    require(build_context() == context, 'Build context changed during verification')
    require(digest(ipa) == before, 'IPA changed during candidate verification')
    return ipa


def stage(manifest, directory):
    """Privately copy and inspect the exact immutable-by-default upload path."""
    original = validate(manifest)
    data = json.loads(manifest.read_text())
    metadata = directory.lstat()
    require(stat.S_ISDIR(metadata.st_mode) and not directory.is_symlink()
            and metadata.st_uid == os.getuid() and metadata.st_mode & 0o077 == 0,
            'Private owned staging directory required')
    destination = directory / 'candidate.ipa'
    with original.open('rb') as src, destination.open('xb') as dst:
        shutil.copyfileobj(src, dst)
        os.fchmod(dst.fileno(), 0o400)
    before = digest(destination)
    require(before == data['sha256'], 'IPA changed during copy')
    actual = inspect_ipa(destination)
    require(digest(destination) == before, 'Upload copy changed during inspection')
    require(all(data.get(k) == v for k, v in actual.items()), 'Upload copy identity changed')
    require(source() == data['commit'], 'Source changed before upload')
    require(build_context() == data.get('build_context'), 'Build context changed before upload')
    require(digest(destination) == before, 'Upload copy changed before use')
    return destination


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation', choices=['source', 'start', 'create', 'validate', 'stage'])
    p.add_argument('--ipa', type=Path)
    p.add_argument('--marker', type=Path)
    p.add_argument('--manifest', type=Path)
    p.add_argument('--version')
    p.add_argument('--build')
    p.add_argument('--staging-dir', type=Path)
    args = p.parse_args()
    try:
        if args.operation == 'source':
            source()
        elif args.operation == 'start':
            sha = source()
            check_ci(sha)
            require(args.marker, 'Build marker path required')
            args.marker.parent.mkdir(parents=True, exist_ok=True)
            args.marker.write_text(json.dumps({'commit': sha, 'branch': 'main', 'build_context': build_context(), 'started_ns': __import__('time').time_ns()}))
        elif args.operation == 'create':
            require(all([args.ipa, args.marker, args.manifest, args.version, args.build]), 'Candidate inputs required')
            create(args.ipa, args.marker, args.manifest, args.version, args.build)
        elif args.operation == 'validate':
            require(args.manifest, 'Candidate manifest required')
            print(validate(args.manifest))
        else:
            require(args.manifest and args.staging_dir, 'Manifest and staging directory required')
            print(stage(args.manifest, args.staging_dir))
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, plistlib.InvalidFileException):
        # Do not leak profile, credential, command output or filesystem contents.
        print('TestFlight verification failed. Preserve source and rebuild/review the exact candidate.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
