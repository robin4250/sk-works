#!/usr/bin/env python3
"""Synthetic artifact regressions; never validate a real signed Release build."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name('audit_release_privacy_artifact.sh')
USAGE_KEYS = (
    'NSFaceIDUsageDescription',
    'NSLocationWhenInUseUsageDescription',
    'NSLocationAlwaysAndWhenInUseUsageDescription',
    'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
)


class PrivacyArtifactFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Runner.app'
        self.app.mkdir()
        self.framework = self.app / 'Frameworks' / 'App.framework'
        self.framework.mkdir(parents=True)
        (self.framework / 'App').write_bytes(b'Synthetic AOT fixture, not executable')
        self.info = {
            'CFBundleIdentifier': 'com.skworks.skWorks',
            'CFBundleShortVersionString': '0.0.fixture',
            'CFBundleVersion': 'fixture',
            'UIBackgroundModes': ['location'],
            **{key: 'Synthetic usage explanation' for key in USAGE_KEYS},
        }
        self.write_info()

    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def snapshot(self):
        return {
            str(path.relative_to(self.app)): path.read_bytes()
            for path in self.app.rglob('*') if path.is_file()
        }

    def run_audit(self):
        before = self.snapshot()
        result = subprocess.run(
            ['bash', str(SCRIPT), str(self.app)],
            check=False, capture_output=True, text=True,
        )
        self.assertEqual(self.snapshot(), before, 'Audit modified artifact bytes')
        self.assertEqual(result.stderr, '')
        return result.returncode, json.loads(result.stdout)

    def test_normal_missing_manifest_is_inventory_not_release_proof(self):
        code, report = self.run_audit()
        self.assertEqual(code, 0)
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['privacy_manifests'], [])
        self.assertTrue(report['release_provenance'].startswith('UNVERIFIED:'))
        self.assertTrue(any('not proof' in text for text in report['remaining_manual_checks']))
        self.assertIn('Frameworks/App.framework', report['framework_inventory'])

    def test_manifest_values_are_reported_without_inventing_reasons(self):
        sdk = self.app / 'Frameworks' / 'FixtureSDK.framework'
        sdk.mkdir()
        reasons = [{'NSPrivacyAccessedAPIType': 'fixture-only-api',
                    'NSPrivacyAccessedAPITypeReasons': ['fixture-only-reason']}]
        (sdk / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({
            'NSPrivacyTracking': False, 'NSPrivacyAccessedAPITypes': reasons,
        }))
        code, report = self.run_audit()
        self.assertEqual(code, 0)
        self.assertEqual(len(report['privacy_manifests']), 1)
        manifest = report['privacy_manifests'][0]
        self.assertEqual(manifest['accessed_api_types'], reasons)
        self.assertFalse(manifest['tracking'])

    def test_invalid_info_plist_fails(self):
        (self.app / 'Info.plist').write_bytes(b'not a plist')
        code, report = self.run_audit()
        self.assertEqual(code, 1)
        self.assertTrue(any('unreadable plist' in error for error in report['errors']))

    def test_invalid_manifest_fails(self):
        (self.app / 'PrivacyInfo.xcprivacy').write_bytes(b'not a plist')
        code, report = self.run_audit()
        self.assertEqual(code, 1)
        self.assertTrue(any('PrivacyInfo.xcprivacy: unreadable plist' in error
                            for error in report['errors']))

    def test_wrong_bundle_id_fails(self):
        self.info['CFBundleIdentifier'] = 'fixture.wrong'
        self.write_info()
        code, report = self.run_audit()
        self.assertEqual(code, 1)
        self.assertIn('Bundle ID must be com.skworks.skWorks', report['errors'])

    def test_missing_usage_description_fails(self):
        del self.info[USAGE_KEYS[0]]
        self.write_info()
        code, report = self.run_audit()
        self.assertEqual(code, 1)
        self.assertIn(f'Missing configured usage description: {USAGE_KEYS[0]}',
                      report['errors'])

    def test_debug_kernel_fails(self):
        assets = self.framework / 'flutter_assets'
        assets.mkdir()
        (assets / 'kernel_blob.bin').write_bytes(b'Synthetic Debug kernel fixture')
        code, report = self.run_audit()
        self.assertEqual(code, 1)
        self.assertTrue(any('kernel_blob.bin' in error for error in report['errors']))


if __name__ == '__main__':
    unittest.main()
