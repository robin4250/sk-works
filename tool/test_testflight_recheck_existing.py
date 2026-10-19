import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch
import testflight_recheck_existing as helper

spec = importlib.util.spec_from_file_location('saved_r31', Path(__file__).with_name('r31_local_release.py'))
r31 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r31)


class RecheckTests(unittest.TestCase):
    def fixture(self, base):
        root=base/'original';root.mkdir();(root/'ios').mkdir();(root/'ios/original').write_text('preserve')
        for args in (['init','-b','main'],['config','user.name','Synthetic'],['config','user.email','fixture@example.invalid']):
            subprocess.run(['git','-C',str(root),*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        (root/'.gitignore').write_text('build/\n');subprocess.run(['git','-C',str(root),'add','.'],check=True)
        subprocess.run(['git','-C',str(root),'commit','-m','fixture'],check=True,stdout=subprocess.DEVNULL)
        old=root/'build/ios/archive';old.mkdir(parents=True);(old/'keep').write_text('old archive')
        stage=base/'tf-candidate-fixture';stage.mkdir();shutil.copytree(root/'ios',stage/'original-ios');shutil.copytree(old,stage/'previous-archive')
        with (stage/'fixture.log').open('wb') as log:
            before=r31.source_state(r31.Runner(root,log))
        r31.write_private(stage/'original-private.json',before)
        r31.write_private(stage/'started-private.json',{'sha':'a'*40,'build_number':'4'})
        r31.write_private(stage/'failed-private.json',{'phase':'candidate_build'})
        r31.write_private(stage/'dependencies-before-private.json',{})
        source=stage/'source';out=source/'build/ios/ipa';out.mkdir(parents=True)
        ipa=out/'preserved.ipa';ipa.write_bytes(b'synthetic-not-signed')
        r31.write_private(source/'build/ios/sko-testflight-build-start.json',{'commit':'a'*40,'branch':'main'})
        (base/'testflight-candidate.lock').touch(mode=0o600)
        calls=[]
        def create(existing,marker,manifest,version,build):
            calls.append('verify_existing');self.assertEqual(existing,ipa);manifest.write_text('{}')
        p=types.SimpleNamespace(__file__=__file__,digest=lambda x:hashlib.sha256(x.read_bytes()).hexdigest(),
                                create=create,validate=lambda _:ipa)
        return root,stage,ipa,p,calls

    def test_reverify_preserves_original_failure_source_and_ipa_without_build(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage,ipa,p,calls=self.fixture(Path(temp));before=ipa.read_bytes();failure=(stage/'failed-private.json').read_bytes()
            def git(runner,*args):
                if args[0]=='fetch':calls.append('fetch_only');return b''
                return r31.Runner.run(runner,['git',*args],True)
            with patch.object(helper.sys,'platform','darwin'),patch.object(r31.Runner,'git',git):
                receipt=helper.recheck(stage,root,'a'*40,'4',p,r31)
            self.assertEqual(calls,['fetch_only','verify_existing'])
            self.assertEqual(ipa.read_bytes(),before);self.assertEqual((stage/'failed-private.json').read_bytes(),failure)
            self.assertFalse(json.loads(receipt.read_text())['rebuilt']);self.assertFalse((stage/'complete-private.json').exists())
            self.assertEqual((root/'build/ios/archive/keep').read_text(),'old archive')

    def test_changed_original_stops_before_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage,ipa,p,calls=self.fixture(Path(temp));(root/'ios/original').write_text('legitimate newer change')
            with patch.object(helper.sys,'platform','darwin'):
                with self.assertRaisesRegex(ValueError,'Original checkout changed'):
                    helper.recheck(stage,root,'a'*40,'4',p,r31)
            self.assertEqual(calls,[]);self.assertEqual((root/'ios/original').read_text(),'legitimate newer change')

    def test_wrong_checkpoint_source_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage,ipa,p,calls=self.fixture(Path(temp))
            with patch.object(helper.sys,'platform','darwin'):
                with self.assertRaisesRegex(ValueError,'Checkpoint source differs'):
                    helper.recheck(stage,root,'b'*40,'4',p,r31)
            self.assertEqual(calls,[])


if __name__=='__main__':unittest.main()
