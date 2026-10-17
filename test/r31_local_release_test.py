"""Synthetic filesystem/Git/CLI boundaries; never connects to production or devices."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('r31', Path(__file__).resolve().parents[1] / 'tool/r31_local_release.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
SHA = 'a' * 40

class SnapshotTests(unittest.TestCase):
    def test_native_cycle_is_link_not_traversal_and_copy_preserves_custom_file(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / 'ios'; root.mkdir()
            (root / 'custom.entitlements').write_text('unchanged')
            (root / 'cycle').symlink_to(root, target_is_directory=True)
            before = m.copy_checked(root, Path(d) / 'saved')
            self.assertEqual(before['cycle'], ['link', str(root)])
            self.assertEqual(len(before), 2)
            (root / 'custom.entitlements').write_text('changed')
            self.assertNotEqual(m.inventory(root), before)

    def test_candidate_internal_absolute_link_is_rebased_without_touching_original(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); original = p / 'original'; original.mkdir()
            (original / 'custom').write_text('kept')
            (original / 'link').symlink_to(original / 'custom')
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            m.isolate_native_links(original, candidate)
            (candidate / 'link').write_text('candidate only')
            self.assertEqual((original / 'custom').read_text(), 'kept')
            self.assertEqual((original / 'link').read_text(), 'kept')

    def test_external_native_links_stop_instead_of_silently_initializing(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); original = p / 'original'; original.mkdir()
            (original / 'outside').symlink_to(p / 'custom-private-file')
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            with self.assertRaisesRegex(RuntimeError, 'explicit reviewed copy plan'):
                m.isolate_native_links(original, candidate)

    def test_inventory_rejects_root_link(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d); (p / 'link').symlink_to(p, target_is_directory=True)
            with self.assertRaises(RuntimeError): m.inventory(p / 'link')

    def test_real_git_dirty_staged_and_untracked_are_preserved_and_changes_detected(self):
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryFile() as log:
            p = Path(d)
            for args in [['init', '-q'], ['config', 'user.name', 'fixture'], ['config', 'user.email', 'fixture@example.invalid']]:
                subprocess.run(['git', '-C', d] + args, check=True)
            (p / 'tracked').write_text('initial')
            subprocess.run(['git', '-C', d, 'add', 'tracked'], check=True)
            subprocess.run(['git', '-C', d, 'commit', '-qm', 'fixture'], check=True)
            (p / 'tracked').write_text('staged')
            subprocess.run(['git', '-C', d, 'add', 'tracked'], check=True)
            (p / 'tracked').write_text('unstaged')
            (p / 'untracked').write_text('keep')
            r = m.Runner(p, log); before = m.source_state(r)
            self.assertTrue(before['staged']); self.assertTrue(before['unstaged'])
            self.assertIn('untracked', before['untracked'])
            self.assertEqual(m.source_state(r), before)
            (p / 'untracked').write_text('changed')
            self.assertNotEqual(m.source_state(r), before)

    def test_release_only_command_and_no_secret_manifest(self):
        c = m.release_command()
        self.assertIn('flutter build ios --release', c[2])
        self.assertNotIn('--debug', c[2]); self.assertNotIn('flutter run', c[2])
        self.assertIn(m.OFF, c[2])
        self.assertNotIn('pbcopy', c[2])

class InstallTests(unittest.TestCase):
    def make_checkpoint(self, d):
        stage = Path(d) / 'checkpoint'; stage.mkdir()
        root = Path(d) / 'original'; root.mkdir()
        native = root / 'ios'; native.mkdir(); (native / 'custom').write_text('kept')
        old = root / 'build/ios/iphoneos/Runner.app'; old.mkdir(parents=True); (old / 'binary').write_text('old')
        source = stage / 'source'; source.mkdir()
        app = source / 'build/ios/iphoneos/Runner.app'; app.mkdir(parents=True); (app / 'binary').write_text('release')
        self.state = {'head': 'b' * 40, 'dirty': 'preserved'}
        self.sig = {'team': 'fixture', 'application': m.BUNDLE, 'keychain': ['original']}
        m.write_private(stage / 'original-private.json', self.state)
        manifest = {'sha': SHA, 'root': str(root), 'source': str(source), 'app_digest': m.digest(app),
                    'signature': self.sig, 'original_native': m.inventory(native),
                    'original_app_digest': m.digest(old),
                    'release_command': ['flutter', 'build', 'ios', '--release', m.OFF],
                    'owner_only': True, 'testflight_approved': False}
        m.write_private(stage / 'built-private.json', manifest)
        return stage, app

    def execute(self, stage, devices=None, sig=None, state=None):
        calls = []
        devices = devices if devices is not None else [{'id': m.DEVICE, 'targetPlatform': 'ios',
                    'name': '13 Pro Max', 'emulator': False, 'isSupported': True}]
        def run(runner, args, capture=False):
            calls.append(args)
            if args[:2] == ['git', 'rev-parse']: return (SHA + '\n').encode()
            if args[:2] == ['git', 'status']: return b''
            if args[:2] == ['flutter', 'devices']: return json.dumps(devices).encode()
        with patch.object(m.Runner, 'run', run), patch.object(m, 'tools_ready'), \
             patch.object(m, 'source_state', return_value=state or self.state), \
             patch.object(m, 'signature', return_value=sig or self.sig):
            m.install(stage)
        return calls

    def test_supported_exact_id_allows_original_phone_name_without_delete_or_rebuild(self):
        with tempfile.TemporaryDirectory() as d:
            stage, app = self.make_checkpoint(d)
            calls = self.execute(stage)
            self.assertEqual([x for x in calls if x[0] == 'xcrun'], [
                ['xcrun', 'devicectl', 'device', 'install', 'app', '--device', m.DEVICE, str(app)],
                ['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', m.DEVICE, m.BUNDLE]])
            self.assertFalse(any('delete' in x or 'flutter build' in x for x in calls))

    def test_tampered_binary_is_refused_before_device_command(self):
        with tempfile.TemporaryDirectory() as d:
            stage, app = self.make_checkpoint(d); (app / 'binary').write_text('tamper')
            with self.assertRaisesRegex(RuntimeError, 'artifact changed'): self.execute(stage)

    def test_changed_signing_identity_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            stage, _ = self.make_checkpoint(d)
            with self.assertRaisesRegex(RuntimeError, 'artifact changed'):
                self.execute(stage, sig={'team': 'different'})

    def test_changed_original_dirty_state_is_refused_without_restore(self):
        with tempfile.TemporaryDirectory() as d:
            stage, _ = self.make_checkpoint(d)
            with self.assertRaisesRegex(RuntimeError, 'original source changed'):
                self.execute(stage, state={'head': 'different'})

    def test_simulator_other_id_and_unsupported_are_refused(self):
        for changes in [{'emulator': True}, {'id': 'other'}, {'isSupported': False}]:
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as d:
                stage, _ = self.make_checkpoint(d)
                device = {'id': m.DEVICE, 'targetPlatform': 'ios', 'emulator': False, 'isSupported': True}
                device.update(changes)
                with self.assertRaisesRegex(RuntimeError, 'physical supported device'):
                    self.execute(stage, devices=[device])

    def test_build_without_completion_manifest_never_installs(self):
        with tempfile.TemporaryDirectory() as d:
            stage, _ = self.make_checkpoint(d); (stage / 'built-private.json').unlink()
            with self.assertRaises(FileNotFoundError): self.execute(stage)

    def test_debug_manifest_refused(self):
        with tempfile.TemporaryDirectory() as d:
            stage, _ = self.make_checkpoint(d)
            p = stage / 'built-private.json'; data = json.loads(p.read_text())
            data['release_command'][3] = '--debug'; p.write_text(json.dumps(data))
            with self.assertRaisesRegex(RuntimeError, 'owner Release checkpoint'): self.execute(stage)

if __name__ == '__main__': unittest.main()
