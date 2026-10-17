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
        self.assertIn('--no-pub', c[2])
        self.assertNotIn('pbcopy', c[2])

class NativeDependencyPlanTests(unittest.TestCase):
    def setup_plan(self, d):
        p = Path(d); original = p / 'ios'; original.mkdir()
        generated = original / '.symlinks/plugins'; generated.mkdir(parents=True)
        cache = p / '.pub-cache'; cache.mkdir()
        package = cache / 'hosted/pub.dev/plugin-one'; package.mkdir(parents=True)
        (package / 'native.m').write_text('original native source')
        (original / 'Runner.entitlements').write_text('keep native signing')
        (generated / 'one').symlink_to(package, target_is_directory=True)
        return p, original, cache, package

    def test_observed_24_cache_and_two_internal_links_are_isolated_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            for i in range(23):
                (original / '.symlinks/plugins' / ('extra-' + str(i))).symlink_to(package)
            (original / 'internal-a').symlink_to(original / 'internal-b')
            (original / 'internal-b').symlink_to(original / 'internal-a')
            before = m.inventory(original); cache_before = m.inventory(cache)
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            deps = p / 'dependencies'
            m.isolate_native_links(original, candidate, cache_root=cache, dependencies=deps)
            self.assertEqual(len(list(deps.iterdir())), 1)
            self.assertEqual((candidate / 'Runner.entitlements').read_text(), 'keep native signing')
            self.assertEqual(len(m.inventory(candidate)), len(before))
            self.assertEqual((candidate / '.symlinks/plugins/one/native.m').read_text(), 'original native source')
            (candidate / '.symlinks/plugins/one/native.m').write_text('isolated build changes')
            self.assertEqual(m.inventory(original), before)
            self.assertEqual(m.inventory(cache), cache_before)
            self.assertEqual((package / 'native.m').read_text(), 'original native source')

    def test_lexical_cache_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            (original / '.symlinks/plugins/one').unlink()
            (original / '.symlinks/plugins/one').symlink_to(cache / '../outside')
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            with self.assertRaisesRegex(RuntimeError, 'outside package cache'):
                m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')

    def test_canonical_cache_symlink_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            outside = p / 'outside'; outside.mkdir()
            (cache / 'alias').symlink_to(outside)
            (original / '.symlinks/plugins/one').unlink()
            (original / '.symlinks/plugins/one').symlink_to(cache / 'alias')
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            with self.assertRaisesRegex(RuntimeError, 'outside canonical cache'):
                m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')

    def test_custom_native_link_is_not_authorized_by_cache_location(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            (original / 'custom-native').symlink_to(package)
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            with self.assertRaisesRegex(RuntimeError, 'custom native external'):
                m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')

    def test_missing_and_looping_external_targets_are_rejected(self):
        for loop in [False, True]:
            with self.subTest(loop=loop), tempfile.TemporaryDirectory() as d:
                p, original, cache, package = self.setup_plan(d)
                target = cache / 'missing-or-loop'
                if loop: target.symlink_to(target)
                (original / '.symlinks/plugins/one').unlink()
                (original / '.symlinks/plugins/one').symlink_to(target)
                candidate = p / 'candidate'; m.copy_checked(original, candidate)
                with self.assertRaises((FileNotFoundError, RuntimeError, OSError)):
                    m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')

    def test_prepare_relinks_only_previously_reviewed_cache_targets_and_final_audit_stops_new_escape(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            deps = p / 'deps'
            approved = m.isolate_native_links(original, candidate, cache_root=cache, dependencies=deps)
            generated = candidate / '.symlinks/plugins/one'
            generated.unlink(); generated.symlink_to(package)
            m.isolate_native_links(candidate, candidate, cache_root=cache, dependencies=deps, approved=approved)
            m.audit_isolated_links(candidate, deps)
            self.assertEqual(len(list(deps.iterdir())), 1)
            generated.unlink(); generated.symlink_to(package)
            with self.assertRaisesRegex(RuntimeError, 'escaped isolated native plan'):
                m.audit_isolated_links(candidate, deps)
            new = cache / 'new'; new.mkdir()
            generated.unlink(); generated.symlink_to(new)
            with self.assertRaisesRegex(RuntimeError, 'unreviewed cache dependency'):
                m.isolate_native_links(candidate, candidate, cache_root=cache, dependencies=deps, approved=approved)

    def test_cache_path_redirect_during_copy_stops_and_never_writes_external_target(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            outside = p / 'outside'; outside.mkdir(); (outside / 'native.m').write_text('do not touch')
            real = m.copy_checked
            def redirected(source, destination):
                before = real(source, destination)
                if Path(source) == package:
                    package.rename(package.with_name('saved-package'))
                    package.symlink_to(outside)
                return before
            with patch.object(m, 'copy_checked', side_effect=redirected):
                with self.assertRaisesRegex(RuntimeError, 'cache path changed'):
                    m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')
            self.assertEqual((outside / 'native.m').read_text(), 'do not touch')
            self.assertEqual((original / 'Runner.entitlements').read_text(), 'keep native signing')

    def test_nested_dependency_escape_stops_without_modifying_cache_or_native(self):
        with tempfile.TemporaryDirectory() as d:
            p, original, cache, package = self.setup_plan(d)
            (package / 'outside').symlink_to(p / 'secret-outside')
            before, cache_before = m.inventory(original), m.inventory(cache)
            candidate = p / 'candidate'; m.copy_checked(original, candidate)
            with self.assertRaisesRegex(RuntimeError, 'explicit reviewed copy plan'):
                m.isolate_native_links(original, candidate, cache_root=cache, dependencies=p / 'deps')
            self.assertEqual(m.inventory(original), before)
            self.assertEqual(m.inventory(cache), cache_before)


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

class FailureDiagnosticTests(unittest.TestCase):
    def tearDown(self):
        m.phase('startup')
        m._STAGE = None

    def test_known_failure_has_fixed_safe_category(self):
        m.phase('tool_preflight')
        record = m.failure_record(m.CheckedFailure('Xcode mismatch'))
        self.assertEqual(record, {'phase': 'tool_preflight', 'kind': 'CheckedFailure',
                                  'category': 'xcode_version'})

    def test_arbitrary_exception_secret_is_not_recorded(self):
        secret = 'sb_secret_example https://private.invalid signing-team@example'
        m.phase('release_build')
        for error in [RuntimeError(secret), m.CheckedFailure(secret),
                      subprocess.CalledProcessError(1, [secret], output=secret)]:
            record = m.failure_record(error)
            self.assertNotIn(secret, json.dumps(record))
            self.assertEqual(record['phase'], 'release_build')

    def test_diagnostics_do_not_write_or_change_checkpoint(self):
        with tempfile.TemporaryDirectory() as d:
            stage = Path(d)
            m.phase('native_snapshot', stage)
            m.failure_record(m.CheckedFailure('copy changed'))
            self.assertEqual(list(stage.iterdir()), [])
