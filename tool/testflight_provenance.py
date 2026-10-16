#!/usr/bin/env python3
"""Fail-closed local release provenance. Never builds, uploads or edits source."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

BUNDLE = 'com.skworks.skWorks'
REQUIRED_CI = {'Flutter CI', 'iOS CI', 'Secret Scan'}


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
    require(run(['git', 'branch', '--show-current']).decode().strip() == 'main', 'main is required')
    require(not run(['git', 'status', '--porcelain', '--untracked-files=all']).strip(),
            'Unsaved source exists; preserve changes before building or uploading')
    sha = run(['git', 'rev-parse', 'HEAD']).decode().strip()
    require(re.fullmatch('[0-9a-f]{40}', sha), 'Invalid commit')
    require(sha == run(['git', 'rev-parse', 'origin/main']).decode().strip(), 'Stale main')
    return sha


def check_ci(sha):
    # gh supplies its existing authentication; neither tokens nor logs are read.
    url = 'repos/robin4250/sk-works/actions/runs?head_sha=' + sha + '&event=push&per_page=100'
    data = json.loads(run(['gh', 'api', url]))
    require(data.get('total_count', 101) <= 100, 'CI results exceed the bounded response; review required')
    result = {}
    for name in REQUIRED_CI:
        runs = [r for r in data.get('workflow_runs', []) if r.get('name') == name
                and r.get('head_sha') == sha and r.get('head_branch') == 'main' and r.get('event') == 'push']
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
                'get_task_allow': False, 'distribution': 'app-store'}


def create(ipa, marker, output, version, build):
    sha = source()
    start = json.loads(marker.read_text())
    require(start.get('commit') == sha and start.get('branch') == 'main', 'Build source changed')
    require(ipa.is_file() and ipa.stat().st_mtime_ns >= start['started_ns'], 'IPA predates this build')
    details = inspect_ipa(ipa)
    require(details['version'] == version and details['build'] == build, 'IPA version/build mismatch')
    ci = check_ci(sha)
    result = {'schema': 1, 'commit': sha, 'branch': 'main', 'build_mode': 'release',
              'ipa': str(ipa.resolve()), 'sha256': digest(ipa), 'ci_runs': ci, **details}
    require(source() == sha, 'Source changed during verification')
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix('.tmp')
    temp.write_text(json.dumps(result, indent=2) + '\n')
    os.replace(temp, output)


def validate(manifest):
    sha = source()
    data = json.loads(manifest.read_text())
    require(data.get('schema') == 1 and data.get('commit') == sha and data.get('branch') == 'main'
            and data.get('build_mode') == 'release', 'Stale or invalid candidate manifest')
    ipa = Path(data['ipa'])
    require(ipa.is_absolute() and ipa.is_file() and digest(ipa) == data.get('sha256'), 'IPA missing or modified')
    actual = inspect_ipa(ipa)
    require(all(data.get(k) == v for k, v in actual.items()), 'IPA identity changed')
    check_ci(sha)
    require(source() == sha, 'Source changed during verification')
    return ipa


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation', choices=['source', 'start', 'create', 'validate'])
    p.add_argument('--ipa', type=Path)
    p.add_argument('--marker', type=Path)
    p.add_argument('--manifest', type=Path)
    p.add_argument('--version')
    p.add_argument('--build')
    args = p.parse_args()
    try:
        if args.operation == 'source':
            source()
        elif args.operation == 'start':
            sha = source()
            check_ci(sha)
            require(args.marker, 'Build marker path required')
            args.marker.parent.mkdir(parents=True, exist_ok=True)
            args.marker.write_text(json.dumps({'commit': sha, 'branch': 'main', 'started_ns': __import__('time').time_ns()}))
        elif args.operation == 'create':
            require(all([args.ipa, args.marker, args.manifest, args.version, args.build]), 'Candidate inputs required')
            create(args.ipa, args.marker, args.manifest, args.version, args.build)
        else:
            require(args.manifest, 'Candidate manifest required')
            print(validate(args.manifest))
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, plistlib.InvalidFileException):
        # Do not leak profile, credential, command output or filesystem contents.
        print('TestFlight verification failed. Preserve source and rebuild/review the exact candidate.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
