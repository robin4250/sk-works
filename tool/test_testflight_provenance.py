#!/usr/bin/env python3
"""Executable synthetic ZIP/signing-tool tests, without Apple credentials/network."""
import datetime as dt
import base64
import importlib.util
import json
import os
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
CONTEXT = {'fixture': 'non-secret-context'}
BUILD_CONTEXT = p.build_context
VERIFY_FLAGS = p.verify_generated_flags


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.addCleanup(patch.stopall)
        patch.object(p, 'build_context', return_value=CONTEXT).start()
        patch.object(p, 'verify_generated_flags').start()
        patch.dict(os.environ, {'SKO_AUDITED_SHA': SHA}).start()
        self.ipa = self.root / 'candidate.ipa'
        self.info = {'CFBundleIdentifier': p.BUNDLE, 'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '42', 'FlutterDeepLinkingEnabled': False, 'CFBundleURLTypes': [{'CFBundleURLSchemes': ['com.skworks.sko']}]}
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

    def test_callback_and_full_entitlement_digest(self):
        first = self.inspect()
        self.ent['keychain-access-groups'] = ['fixture-group']
        self.assertNotEqual(first['effective_entitlements_sha256'], self.inspect()['effective_entitlements_sha256'])
        self.info['FlutterDeepLinkingEnabled'] = True
        self.write_zip()
        with self.assertRaises(ValueError): self.inspect()
        self.info['FlutterDeepLinkingEnabled'] = False
        self.info['CFBundleURLTypes'] = []
        self.write_zip()
        with self.assertRaises(ValueError): self.inspect()

    def test_native_context_allowlist_excludes_credentials_and_rejects_symlinks(self):
        repo = self.root / 'context'
        required = ['ios/Runner/Info.plist', 'ios/Runner.xcodeproj/project.pbxproj',
                    'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme']
        for name in required:
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (repo / 'tool').mkdir()
        secret = repo / 'tool/local_supabase_env.sh'
        secret.write_text('fixture-secret-do-not-hash')
        commands = [json.dumps({'frameworkVersion': '3.47.5', 'frameworkRevision': 'fixture'}).encode(),
                    b'Xcode 27.1\nBuild version 27A9275']
        old = Path.cwd()
        try:
            os.chdir(repo)
            with patch.object(p, 'run', side_effect=commands): first = BUILD_CONTEXT()
            secret.write_text('different-fixture-secret')
            with patch.object(p, 'run', side_effect=commands): self.assertEqual(first, BUILD_CONTEXT())
            self.assertEqual(set(first['native_sha256']), set(required))
            path = repo / required[0]
            path.unlink()
            path.symlink_to(secret)
            with self.assertRaises(ValueError): BUILD_CONTEXT()
        finally:
            os.chdir(old)

    def test_old_manifest_and_changed_native_context_rejected(self):
        manifest = self.root / 'manifest.json'
        data = {'schema': 2, 'audited_commit': SHA, 'build_context': CONTEXT,
                'commit': SHA, 'branch': 'main', 'build_mode': 'release',
                'ipa': str(self.ipa), 'sha256': p.digest(self.ipa), **self.inspect()}
        with patch.object(p, 'source', return_value=SHA):
            manifest.write_text(json.dumps({**data, 'schema': 1}))
            with self.assertRaises(ValueError): p.validate(manifest)
            manifest.write_text(json.dumps(data))
            with patch.object(p, 'build_context', return_value={'changed': True}):
                with self.assertRaises(ValueError): p.validate(manifest)

    def test_generated_compile_flags_are_checked_without_saved_secrets(self):
        root = self.root / 'flags'
        path = root / 'ios/Flutter/Generated.xcconfig'
        path.parent.mkdir(parents=True)
        flags = {'SUPABASE_URL': 'https://ztktgquxvcxcjxtluspu.supabase.co',
                 'SUPABASE_PUBLISHABLE_KEY': 'synthetic-public-fixture',
                 'SKO_MASTER_PASSWORD_V1': 'false'}
        def write(values):
            path.write_text('DART_DEFINES=' + ','.join(base64.b64encode((k+'='+v).encode()).decode() for k,v in values.items()))
        old = Path.cwd()
        try:
            os.chdir(root)
            write(flags)
            self.assertIsNone(VERIFY_FLAGS())
            for changed in [{**flags, 'SKO_MASTER_PASSWORD_V1': 'true'},
                            {**flags, 'UNREVIEWED_FLAG': 'true'},
                            {**flags, 'SUPABASE_URL': 'https://example.invalid'}]:
                write(changed)
                with self.assertRaises(ValueError): VERIFY_FLAGS()
        finally:
            os.chdir(old)

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
        with patch.object(p, 'run', return_value=json.dumps({'total_count': len(runs), 'workflow_runs': runs}).encode()):
            self.assertEqual(len(p.check_ci(SHA)), len(p.REQUIRED_CI))
            with self.assertRaises(ValueError): p.check_ci('b' * 40)
        runs.append({**runs[0], 'id': 99, 'run_number': 2, 'conclusion': 'failure'})
        with patch.object(p, 'run', return_value=json.dumps({'total_count': len(runs), 'workflow_runs': runs}).encode()):
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
        env = dict(os.environ, SKO_AUDITED_SHA=sha)
        clean = subprocess.run(['python3', script, 'source'], cwd=repo, capture_output=True, env=env)
        self.assertEqual(clean.returncode, 0)
        for audited in ['', 'b' * 40]:
            refused = subprocess.run(['python3', script, 'source'], cwd=repo, capture_output=True,
                                     env=dict(env, SKO_AUDITED_SHA=audited))
            self.assertNotEqual(refused.returncode, 0)
        (repo / 'saved.txt').write_text('unsaved')
        (repo / 'untracked.txt').write_text('keep')
        result = subprocess.run(['python3', script, 'source'], cwd=repo, capture_output=True, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((repo / 'saved.txt').read_text(), 'unsaved')
        self.assertEqual((repo / 'untracked.txt').read_text(), 'keep')

    def test_manual_main_ci_is_allowed_only_on_exact_commit(self):
        runs = [{'id': i, 'name': name, 'head_sha': SHA, 'head_branch': 'main', 'event': 'workflow_dispatch',
                 'run_number': 1, 'status': 'completed', 'conclusion': 'success'}
                for i, name in enumerate(p.REQUIRED_CI)]
        with patch.object(p, 'run', return_value=json.dumps({'total_count': len(runs), 'workflow_runs': runs}).encode()):
            self.assertEqual(len(p.check_ci(SHA)), len(p.REQUIRED_CI))
            with self.assertRaises(ValueError): p.check_ci('b' * 40)
        runs[0]['head_branch'] = 'other'
        with patch.object(p, 'run', return_value=json.dumps({'total_count': len(runs), 'workflow_runs': runs}).encode()):
            with self.assertRaises(ValueError): p.check_ci(SHA)

    def test_manifest_tamper_stale_and_identity(self):
        manifest = self.root / 'manifest.json'
        data = {'schema': 2, 'audited_commit': SHA, 'build_context': CONTEXT, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
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
        marker.write_text(json.dumps({'commit': SHA, 'branch': 'main', 'build_context': CONTEXT, 'started_ns': self.ipa.stat().st_mtime_ns + 1000000000}))
        with patch.object(p, 'source', return_value=SHA):
            with self.assertRaises(ValueError): p.create(self.ipa, marker, self.root / 'out.json', '1.2.3', '42')

    def test_create_rejects_mutation_during_inspection(self):
        marker = self.root / 'start.json'
        marker.write_text(json.dumps({'commit': SHA, 'branch': 'main', 'build_context': CONTEXT, 'started_ns': self.ipa.stat().st_mtime_ns - 1}))
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
        manifest.write_text(json.dumps({'schema': 2, 'audited_commit': SHA, 'build_context': CONTEXT, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
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
        manifest.write_text(json.dumps({'schema': 2, 'audited_commit': SHA, 'build_context': CONTEXT, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
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
        manifest.write_text(json.dumps({'schema': 2, 'audited_commit': SHA, 'build_context': CONTEXT, 'commit': SHA, 'branch': 'main', 'build_mode': 'release',
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
