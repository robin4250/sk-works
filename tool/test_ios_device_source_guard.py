"""Real Git / simulated Mac command fixtures; no build, signing or device proof."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = 'c0185ca7d354c7d78e5c6d08b49d64ff54916c1c'


class DeviceSourceGuardTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.remote, self.repo, self.bin = root/'remote.git', root/'repo', root/'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                        PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        SUPABASE_URL='https://fixture.invalid', SUPABASE_PUBLISHABLE_KEY='fixture-public',
                        FIXTURE_MARKERS=str(root/'markers'))
        self.markers = root/'markers'
        self.cmd('git', 'init', '--bare', '--initial-branch=main', str(self.remote), cwd=root)
        self.cmd('git', 'clone', str(self.remote), str(self.repo), cwd=root)
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        (self.repo/'tool').mkdir()
        for name in ['ios_device_source_guard.sh', 'run_ios_device.sh']:
            shutil.copyfile(ROOT/'tool'/name, self.repo/'tool'/name)
        (self.repo/'.gitignore').write_text('tool/local_supabase_env.sh\n')
        (self.repo/'tool/prepare_ios.sh').write_text('echo generated >> "$FIXTURE_MARKERS"\nexit 91\n')
        self.git('add', '.')
        self.git('commit', '-m', 'fixture')
        self.git('push', 'origin', 'main')
        self.sha = self.git('rev-parse', 'HEAD').stdout.strip()
        self.stub('uname', 'printf "%s\\n" "${FIXTURE_OS:-Darwin}"')
        self.stub('flutter', 'printf "Flutter %s\\n" "${FIXTURE_FLUTTER:-3.47.5}"')
        self.stub('xcodebuild', 'printf "Xcode %s\\nBuild version fixture\\n" "${FIXTURE_XCODE:-27.0}"')
        self.stub('xcrun', 'exit 99')

    def cmd(self, *args, cwd=None):
        result = subprocess.run(args, cwd=cwd or self.repo, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def git(self, *args):
        return self.cmd('git', *args)

    def stub(self, name, content):
        path = self.bin/name
        path.write_text('#!/usr/bin/env bash\n'+content+'\n')
        path.chmod(0o700)

    def guard(self, expected=None):
        args = ['bash', 'tool/ios_device_source_guard.sh']
        if expected is not None:
            args.append(expected)
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True, capture_output=True)

    def runner(self):
        return subprocess.run(['bash', 'tool/run_ios_device.sh', 'fixture-device'], cwd=self.repo,
                              env=self.env, text=True, capture_output=True)

    def test_exact_original_runner_passes_stale_source_into_generation_fixed_refuses(self):
        old = subprocess.check_output(['git', '-C', str(ROOT), 'show', ORIGINAL+':tool/run_ios_device.sh'])
        (self.repo/'tool/run_ios_device.sh').write_bytes(old)
        self.git('add', '.')
        self.git('commit', '-m', 'original runner')  # Deliberately differs from remote main.
        result = self.runner()
        self.assertEqual(result.returncode, 91, result.stderr)
        self.assertEqual(self.markers.read_text(), 'generated\n', 'original must demonstrate the generation bypass')
        self.markers.unlink()
        shutil.copyfile(ROOT/'tool/run_ios_device.sh', self.repo/'tool/run_ios_device.sh')
        self.git('add', '.')
        self.git('commit', '-m', 'corrected runner')
        result = self.runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('最新main', result.stderr)
        self.assertFalse(self.markers.exists(), 'corrected runner must refuse before generation')
        print('PASS exact original stale-source generation bypass; corrected runner refuses before generation')

    def test_fresh_clean_source_reaches_generation_without_build_or_install(self):
        self.assertEqual(self.guard().stdout.strip(), self.sha)
        self.assertEqual(self.runner().returncode, 91)
        self.assertEqual(self.markers.read_text(), 'generated\n')

    def test_dirty_tracked_untracked_branch_and_unavailable_remote_refuse(self):
        for path in [self.repo/'dirty.txt', self.repo/'tool/prepare_ios.sh']:
            before = path.read_bytes() if path.exists() else None
            path.write_text('preserve me\n')
            self.assertNotEqual(self.runner().returncode, 0)
            self.assertFalse(self.markers.exists())
            self.assertEqual(path.read_text(), 'preserve me\n')
            if before is None:
                path.unlink()
            else:
                path.write_bytes(before)
        self.git('switch', '-c', 'review')
        self.assertNotEqual(self.guard().returncode, 0)
        self.git('switch', 'main')
        self.git('remote', 'set-url', 'origin', str(self.remote/'missing'))
        self.assertNotEqual(self.runner().returncode, 0)
        self.assertFalse(self.markers.exists())

    def test_exact_toolchain_requires_mac_flutter_and_xcode_without_bypass(self):
        for key, value in [('FIXTURE_OS', 'Linux'), ('FIXTURE_FLUTTER', '3.47.4'), ('FIXTURE_XCODE', '27.1')]:
            self.env[key] = value
            self.env['SKO_DEVICE_SOURCE_VERIFIED'] = 'true'  # No production bypass exists.
            self.assertNotEqual(self.runner().returncode, 0)
            self.assertFalse(self.markers.exists())
            self.env.pop(key)

    def test_preinstall_recheck_rejects_changed_sha_dirty_and_new_remote_main(self):
        self.assertEqual(self.guard(self.sha).returncode, 0)
        (self.repo/'new.txt').write_text('saved new source')
        self.git('add', '.')
        self.git('commit', '-m', 'source changed after build')
        self.git('push', 'origin', 'main')
        self.assertNotEqual(self.guard(self.sha).returncode, 0)
        new = self.git('rev-parse', 'HEAD').stdout.strip()
        (self.repo/'untracked.txt').write_text('retain')
        self.assertNotEqual(self.guard(new).returncode, 0)
        (self.repo/'untracked.txt').unlink()
        other = Path(self.temp.name)/'other'
        self.cmd('git', 'clone', str(self.remote), str(other))
        self.cmd('git', 'config', 'user.email', 'fixture@example.invalid', cwd=other)
        self.cmd('git', 'config', 'user.name', 'Fixture', cwd=other)
        (other/'advance.txt').write_text('new remote main')
        self.cmd('git', 'add', '.', cwd=other)
        self.cmd('git', 'commit', '-m', 'remote advances', cwd=other)
        self.cmd('git', 'push', 'origin', 'main', cwd=other)
        self.assertNotEqual(self.guard(new).returncode, 0)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), new)

    def test_ignored_settings_preserved_and_recheck_precedes_install(self):
        settings = self.repo/'tool/local_supabase_env.sh'
        settings.write_text('# retained private local fixture setting\n')
        self.assertEqual(self.guard(self.sha).returncode, 0)
        self.assertEqual(settings.read_text(), '# retained private local fixture setting\n')
        source = (ROOT/'tool/run_ios_device.sh').read_text()
        self.assertLess(source.index('release_source_sha='), source.index('source "tool/local_supabase_env.sh"'))
        self.assertLess(source.index('bash tool/ios_device_source_guard.sh "$release_source_sha"'), source.index('xcrun devicectl device install app'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
