#!/usr/bin/env python3
"""Executable synthetic ZIP/signing-tool tests, without Apple credentials/network."""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('provenance', Path(__file__).with_name('testflight_provenance.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
SHA = 'a' * 40


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.ipa = self.root / 'candidate.ipa'
        self.info = {'CFBundleIdentifier': p.BUNDLE, 'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '42'}
        self.ent = {'application-identifier': 'PREFIX1234.' + p.BUNDLE,
                    'com.apple.developer.team-identifier': 'TEAM123456', 'get-task-allow': False}
        self.profile = {'TeamIdentifier': ['TEAM123456'], 'Entitlements': {**self.ent, 'beta-reports-active': True},
                        'ExpirationDate': dt.datetime(2099, 1, 1), 'DeveloperCertificates': [b'fixture-cert']}
        self.entries = {}
        self.write_zip()

    def write_zip(self):
        with zipfile.ZipFile(self.ipa, 'w') as z:
            z.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(self.info))
            z.writestr('Payload/Runner.app/Frameworks/App.framework/App', b'fixture-not-executable')
            z.writestr('Payload/Runner.app/embedded.mobileprovision', b'fixture-not-signed')
            for key, value in self.entries.items():
                z.writestr(key, value)

    def command(self, args):
        if args[0] == '/usr/bin/security':
            return plistlib.dumps(self.profile)
        if '--extract-certificates' in args:
            Path(args[args.index('--extract-certificates') + 1] + '0').write_bytes(b'fixture-cert')
            return b''
        if '--entitlements' in args:
            return plistlib.dumps(self.ent)
        if '--verify' in args:
            return b''
        self.fail('Unexpected command')

    def inspect(self):
        with patch.object(p.sys, 'platform', 'darwin'), patch.object(p, 'run', side_effect=self.command):
            return p.inspect_ipa(self.ipa)

    def test_distribution_zip_identity(self):
        result = self.inspect()
        self.assertEqual(result['build'], '42')
        self.assertFalse(result['get_task_allow'])

    def test_bundle_debug_ats_rejections(self):
        for key, value in [('CFBundleIdentifier', 'wrong'), ('NSAppTransportSecurity', {'NSAllowsArbitraryLoads': True})]:
            original = dict(self.info)
            self.info[key] = value
            self.write_zip()
            with self.assertRaises(ValueError): self.inspect()
            self.info = original
        self.entries['Payload/Runner.app/flutter_assets/kernel_blob.bin'] = b'debug'
        self.write_zip()
        with self.assertRaises(ValueError): self.inspect()

    def test_invalid_signing_and_profiles(self):
        for mutate in [lambda: self.ent.update({'get-task-allow': True}),
                       lambda: self.profile.update({'TeamIdentifier': ['OTHER12345']}),
                       lambda: self.profile.update({'ProvisionedDevices': ['fixture']}),
                       lambda: self.profile.update({'ProvisionsAllDevices': True}),
                       lambda: self.profile.update({'ExpirationDate': dt.datetime(2000, 1, 1)}),
                       lambda: self.profile.update({'DeveloperCertificates': [b'wrong-cert']}),
                       lambda: self.profile['Entitlements'].update({'beta-reports-active': False})]:
            ent, profile = dict(self.ent), plistlib.loads(plistlib.dumps(self.profile))
            mutate()
            with self.assertRaises(ValueError): self.inspect()
            self.ent, self.profile = ent, profile

    def test_unsigned_fails(self):
        with patch.object(p.sys, 'platform', 'darwin'), patch.object(p, 'run', side_effect=ValueError('unsigned')):
            with self.assertRaises(ValueError): p.inspect_ipa(self.ipa)

    def test_zip_traversal_rejected_before_tools(self):
        self.entries['../escape'] = b'bad'
        self.write_zip()
        with self.assertRaises(ValueError): self.inspect()
        self.assertFalse((self.root / 'escape').exists())

    def test_linux_cannot_bypass_signature_validation(self):
        with patch.object(p.sys, 'platform', 'linux'):
            with self.assertRaises(ValueError): p.inspect_ipa(self.ipa)

    def test_ci_exact_sha_and_latest_failure(self):
        runs = [{'id': i, 'name': name, 'head_sha': SHA, 'head_branch': 'main', 'event': 'push',
                 'run_number': 1, 'status': 'completed', 'conclusion': 'success'}
                for i, name in enumerate(p.REQUIRED_CI)]
        with patch.object(p, 'run', return_value=json.dumps({'total_count': 3, 'workflow_runs': runs}).encode()):
            self.assertEqual(len(p.check_ci(SHA)), 3)
            with self.assertRaises(ValueError): p.check_ci('b' * 40)
        runs.append({**runs[0], 'id': 99, 'run_number': 2, 'conclusion': 'failure'})
        with patch.object(p, 'run', return_value=json.dumps({'total_count': 4, 'workflow_runs': runs}).encode()):
            with self.assertRaises(ValueError): p.check_ci(SHA)

    def test_dirty_real_git_checkout_is_preserved(self):
        subprocess.run(['git', 'init', '-b', 'main', str(self.root / 'repo')], check=True, capture_output=True)
        repo = self.root / 'repo'
        (repo / 'saved.txt').write_text('saved')
        for args in [['add', '.'], ['-c', 'user.email=fixture@example.invalid', '-c', 'user.name=Fixture', 'commit', '-m', 'fixture']]:
            subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
        sha = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip()
        subprocess.run(['git', '-C', str(repo), 'update-ref', 'refs/remotes/origin/main', sha], check=True)
        script = str(Path(p.__file__).resolve())
        clean = subprocess.run(['python3', script, 'source'], cwd=repo, capture_output=True)
        self.assertEqual(clean.returncode, 0)
        (repo / 'saved.txt').write_text('unsaved')
        (repo / 'untracked.txt').write_text('keep')
        result = subprocess.run(['python3', script, 'source'], cwd=repo, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((repo / 'saved.txt').read_text(), 'unsaved')
        self.assertEqual((repo / 'untracked.txt').read_text(), 'keep')

    def test_manifest_tamper_stale_and_identity(self):
        manifest = self.root / 'manifest.json'
        data = {'schema': 1, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
                'ipa': str(self.ipa), 'sha256': p.digest(self.ipa), **self.inspect()}
        manifest.write_text(json.dumps(data))
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'check_ci'), patch.object(p.sys, 'platform', 'darwin'), patch.object(p, 'run', side_effect=self.command):
            self.assertEqual(p.validate(manifest), self.ipa)
            for key, value in [('commit', 'b' * 40), ('build_mode', 'debug'), ('build', '41')]:
                manifest.write_text(json.dumps({**data, key: value}))
                with self.assertRaises(ValueError): p.validate(manifest)
            manifest.write_text(json.dumps(data))
            self.ipa.write_bytes(self.ipa.read_bytes() + b'tampered')
            with self.assertRaises(ValueError): p.validate(manifest)

    def test_old_ipa_cannot_create_candidate(self):
        marker = self.root / 'start.json'
        marker.write_text(json.dumps({'commit': SHA, 'branch': 'main', 'started_ns': self.ipa.stat().st_mtime_ns + 1000000000}))
        with patch.object(p, 'source', return_value=SHA):
            with self.assertRaises(ValueError): p.create(self.ipa, marker, self.root / 'out.json', '1.2.3', '42')

    def test_create_rejects_mutation_during_inspection(self):
        marker = self.root / 'start.json'
        marker.write_text(json.dumps({'commit': SHA, 'branch': 'main', 'started_ns': self.ipa.stat().st_mtime_ns - 1}))
        details = self.inspect()
        def mutate(path):
            path.write_bytes(path.read_bytes() + b'changed-during-inspection')
            return details
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'inspect_ipa', side_effect=mutate), patch.object(p, 'check_ci'):
            with self.assertRaises(ValueError): p.create(self.ipa, marker, self.root / 'out.json', '1.2.3', '42')
        self.assertFalse((self.root / 'out.json').exists())

    def test_validate_rejects_mutation_during_inspection(self):
        manifest = self.root / 'manifest.json'
        details = self.inspect()
        manifest.write_text(json.dumps({'schema': 1, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
            'ipa': str(self.ipa), 'sha256': p.digest(self.ipa), **details}))
        def mutate(path):
            path.write_bytes(path.read_bytes() + b'changed-during-inspection')
            return details
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'inspect_ipa', side_effect=mutate), patch.object(p, 'check_ci'):
            with self.assertRaises(ValueError): p.validate(manifest)

    def test_stage_preserves_original_and_inspects_exact_read_only_copy(self):
        manifest = self.root / 'manifest.json'
        details = self.inspect()
        original = self.ipa.read_bytes()
        manifest.write_text(json.dumps({'schema': 1, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
            'ipa': str(self.ipa), 'sha256': p.digest(self.ipa), **details}))
        staging = self.root / 'private'
        staging.mkdir(mode=0o700)
        seen = []
        def inspect(path):
            seen.append(path)
            return details
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'inspect_ipa', side_effect=inspect), patch.object(p, 'check_ci'):
            destination = p.stage(manifest, staging)
        self.assertEqual(seen, [self.ipa, destination])
        self.assertEqual(destination, staging / 'candidate.ipa')
        self.assertEqual(destination.stat().st_mode & 0o777, 0o400)
        self.assertEqual(destination.read_bytes(), original)
        self.assertEqual(self.ipa.read_bytes(), original)

    def test_stage_rejects_changed_copy_and_public_directory(self):
        manifest = self.root / 'manifest.json'
        details = self.inspect()
        manifest.write_text(json.dumps({'schema': 1, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
            'ipa': str(self.ipa), 'sha256': p.digest(self.ipa), **details}))
        staging = self.root / 'public'
        staging.mkdir(mode=0o755)
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'inspect_ipa', return_value=details), patch.object(p, 'check_ci'):
            with self.assertRaises(ValueError): p.stage(manifest, staging)
        staging.chmod(0o700)
        def inspect(path):
            if path != self.ipa:
                path.chmod(0o600)
                path.write_bytes(path.read_bytes() + b'changed-copy')
            return details
        with patch.object(p, 'source', return_value=SHA), patch.object(p, 'inspect_ipa', side_effect=inspect), patch.object(p, 'check_ci'):
            with self.assertRaises(ValueError): p.stage(manifest, staging)


if __name__ == '__main__':
    unittest.main()
