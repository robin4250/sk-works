import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parent))
import testflight_private_candidate as module


class PrivateCandidateTests(unittest.TestCase):
    def test_durable_duplicate_and_unknown_refusal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);stage=root/'tf-candidate-one';stage.mkdir()
            module.r31.write_private(stage/'started-private.json',{'sha':'a'*40,'build_number':'8'})
            with self.assertRaisesRegex(RuntimeError,'unknown'):module.reject_previous(root,'b'*40,'9')
            module.r31.write_private(stage/'complete-private.json',{})
            with self.assertRaisesRegex(RuntimeError,'already attempted'):module.reject_previous(root,'a'*40,'8')
            module.reject_previous(root,'b'*40,'9')

    def test_existing_candidate_command_no_upload_or_install(self):
        command=module.candidate_command(Path('/private/original-env'),Path('/private/stage'),'a'*40,'9',Path('/private/icon'),'0.2.0')
        self.assertIn('flutter build ipa --release --no-pub',command[2]);self.assertIn('bash tool/testflight_preflight.sh',command[2]);self.assertIn('testflight_provenance.py start',command[2])
        for forbidden in ('testflight_finish','testflight_upload','altool','devicectl','flutter run'):
            self.assertNotIn(forbidden,' '.join(command))
        self.assertIn('source "$1"',command[2])

    def test_dirty_original_preserved_and_old_archive_copied(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary);root=base/'repo';root.mkdir();backups=base/'backups'
            def git(*args):return subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL)
            git('init','-b','main');git('config','user.name','Synthetic');git('config','user.email','fixture@example.invalid')
            (root/'ios').mkdir();(root/'ios/tracked').write_text('original native');(root/'tool').mkdir();(root/'tool/local_supabase_env.sh').write_text('synthetic environment')
            (root/'pubspec.yaml').write_text('version: 0.2.0+3\n');(root/'.gitignore').write_text('build/\ntool/local_supabase_env.sh\n');(root/'file').write_text('base');git('add','.');git('commit','-m','fixture');sha=git('rev-parse','HEAD').decode().strip()
            git('update-ref','refs/remotes/origin/main',sha)
            (root/'file').write_text('staged');git('add','file');(root/'file').write_text('unstaged');(root/'untracked').write_text('SYNTHETIC_PRIVATE_VALUE')
            (root/'assets/branding').mkdir(parents=True);(root/'assets/branding/SKO正式アイコン.png').write_bytes(b'synthetic icon')
            old=root/'build/ios/archive/Old.xcarchive';old.mkdir(parents=True);(old/'keep').write_text('old artifact')
            real=module.r31.Runner
            class FakeRunner(real):
                def run(self,args,capture=False):
                    if args[:3]==['git','fetch','--no-tags']:return b'' if capture else None
                    if args[0]=='env' or args[0]=='bash' or args[:2]==['bash','tool/prepare_ios.sh']:
                        if 'flutter build ipa --release --no-pub' in ' '.join(args):
                            ipa=self.cwd/'build/ios/ipa/candidate.ipa';ipa.parent.mkdir(parents=True,exist_ok=True);ipa.write_bytes(b'synthetic IPA')
                            p=self.cwd/'build/ios/sko-testflight-provenance.json';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps({'commit':sha,'build':'9','bundle_id':module.r31.BUNDLE,'distribution':'app-store','sha256':'b'*64}))
                        return b'' if capture else None
                    return super().run(args,capture)
            # Synthetic lifecycle: no SDK/network/build commands are executed.
            with patch.object(module.sys,'platform','darwin'),patch.object(module.r31,'Runner',FakeRunner),patch.object(module.r31,'tools_ready'),patch.object(module.r31,'audit_isolated_links'):
                before=module.r31.source_state(real(root,subprocess.DEVNULL))
                stage=module.build(root,sha,'9',backups)
                after=module.r31.source_state(real(root,subprocess.DEVNULL))
            self.assertEqual(before,after)
            self.assertEqual((stage/'previous-archive/Old.xcarchive/keep').read_text(),'old artifact')
            self.assertEqual((stage/'untracked-before/untracked').read_text(),'SYNTHETIC_PRIVATE_VALUE')
            self.assertFalse((stage/'source/tool/local_supabase_env.sh').exists())
            self.assertTrue((stage/'complete-private.json').exists())


if __name__=='__main__':unittest.main()
