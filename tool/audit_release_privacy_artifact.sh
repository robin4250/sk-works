#!/usr/bin/env bash
# Read-only inspection of an actual built iOS application. No signing/build changes.
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/Runner.app" >&2
  exit 2
fi
python3 - "$1" <<'PY'
import json
import pathlib
import plistlib
import sys

app = pathlib.Path(sys.argv[1]).expanduser().resolve()
if app.suffix != '.app' or not app.is_dir():
    raise SystemExit('ERROR: supply an existing built Runner.app directory')
errors = []

def read_plist(path):
    try:
        with path.open('rb') as stream:
            return plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        errors.append(f'{path.relative_to(app)}: unreadable plist ({error})')
        return {}

info = read_plist(app / 'Info.plist')
if info.get('CFBundleIdentifier') != 'com.skworks.skWorks':
    errors.append('Bundle ID must be com.skworks.skWorks')
# A built Info.plist alone does not identify Flutter Release reliably. Check the
# framework snapshot artifact and explicit development indicators, then require
# separate build/archive provenance before declaring the Release gate complete.
if info.get('get-task-allow') is True:
    errors.append('Info.plist contains development get-task-allow=true')
flutter = app / 'Frameworks' / 'App.framework'
if (flutter / 'flutter_assets' / 'kernel_blob.bin').exists():
    errors.append('Flutter kernel_blob.bin found: this is not a Release artifact')
if not (flutter / 'App').is_file():
    errors.append('Flutter AOT App.framework/App executable is missing')
required = [
    'NSFaceIDUsageDescription', 'NSLocationWhenInUseUsageDescription',
    'NSLocationAlwaysAndWhenInUseUsageDescription', 'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
]
missing = [key for key in required if not isinstance(info.get(key), str) or not info[key].strip()]
errors.extend(f'Missing configured usage description: {key}' for key in missing)
if 'location' not in info.get('UIBackgroundModes', []):
    errors.append('Configured GPS background location mode is missing')
manifests = []
for path in sorted(app.rglob('PrivacyInfo.xcprivacy')):
    value = read_plist(path)
    manifests.append({
        'path': str(path.relative_to(app)),
        'tracking': value.get('NSPrivacyTracking'),
        'tracking_domains': value.get('NSPrivacyTrackingDomains', []),
        'collected_data_types': value.get('NSPrivacyCollectedDataTypes', []),
        'accessed_api_types': value.get('NSPrivacyAccessedAPITypes', []),
    })
frameworks = sorted(str(path.relative_to(app)) for path in (app / 'Frameworks').glob('*.framework'))
report = {
    'artifact': str(app), 'bundle_id': info.get('CFBundleIdentifier'),
    'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion'),
    'minimum_os_version': info.get('MinimumOSVersion'),
    'release_provenance': 'UNVERIFIED: check Release build/archive logs and signing entitlements separately',
    'usage_descriptions': {key: info.get(key) for key in required},
    'background_modes': info.get('UIBackgroundModes', []),
    'framework_inventory': frameworks, 'privacy_manifests': manifests,
    'errors': errors,
    'remaining_manual_checks': [
        'Confirm Release build/archive provenance; AOT can also appear in Profile builds.',
        'Inspect signed entitlements and SDK signatures on the Mac.',
        'Match each required-reason API declaration to actual app/SDK behavior.',
        'Validate SDK requirements and complete App Store privacy labels using actual collection and network behavior.',
        'No manifest found is an inventory result, not proof that a manifest is unnecessary.',
    ],
}
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1 if errors else 0)
PY
