import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import struct
import unittest
from unittest.mock import patch
import pymupdf
import inspection_worker_candidate as worker


@unittest.skipUnless(sys.platform == 'linux', 'POSIX Linux resource-limit candidate')
class WorkerCandidateTest(unittest.TestCase):
    def setUp(self):
        with pymupdf.open() as doc:
            doc.new_page().insert_text((72, 72), 'Only Owner\nPayroll fixture 90000')
            self.pdf = doc.tobytes()
        self.digest = hashlib.sha256(self.pdf).hexdigest()

    def observe(self, data=None, **options):
        return worker.observe_in_worker(self.pdf if data is None else data,
            expected_sha256=options.pop('expected_sha256', self.digest),
            expected_owner=options.pop('expected_owner', 'Only Owner'),
            enabled=options.pop('enabled', True), **options)

    def test_real_parser_returns_only_exact_observations_and_preserves_original(self):
        before = bytes(self.pdf)
        result = self.observe()
        self.assertEqual(result['pdf_sha256'], self.digest)
        self.assertEqual(result['page_count'], 1)
        self.assertEqual(set(result), {'candidate_policy','pdf_sha256','page_count','text_sha256'})
        self.assertEqual(self.pdf, before)
        self.assertNotIn('Only Owner', json.dumps(result))
        self.assertNotIn('passed', result)

    def test_default_off_invalid_digest_owner_and_config_never_spawn(self):
        with patch.object(worker.subprocess, 'Popen', side_effect=AssertionError('must not spawn')):
            for options in ({'enabled':False}, {'expected_sha256':'a'*64},
                            {'expected_owner':''}, {'forbidden_markers':['x']*129},
                            {'timeout_seconds':float('nan')}, {'timeout_seconds':True}):
                with self.subTest(options=options), self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                    self.observe(**options)

    def test_actual_pdf_rejections_are_generic_and_original_unchanged(self):
        for options in ({'expected_owner':'Foreign Owner'}, {'forbidden_markers':['90000']}):
            with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                self.observe(**options)
        with pymupdf.open(stream=self.pdf, filetype='pdf') as doc:
            doc.embfile_add('secret.txt', b'secret-original')
            attached = doc.tobytes()
        before = bytes(attached)
        with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
            self.observe(attached, expected_sha256=hashlib.sha256(attached).hexdigest())
        self.assertEqual(attached, before)
        with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
            self.observe(b'%PDF-invalid fixture', expected_sha256=hashlib.sha256(b'%PDF-invalid fixture').hexdigest())

    def run_fault(self, code, timeout=.5):
        # Controlled child programs exercise supervisor faults, not parser proof.
        with tempfile.TemporaryFile() as source:
            return worker._supervise(source, self.digest, timeout,
                                     [sys.executable, '-I', '-c', code])

    def test_wrong_output_duplicate_keys_extra_text_and_error_stderr_never_escape(self):
        good={'candidate_policy':worker.POLICY,'pdf_sha256':self.digest,
              'page_count':1,'text_sha256':'a'*64}
        variants=[json.dumps({**good,'passed':True}), json.dumps({**good,'pdf_sha256':'b'*64}),
                  json.dumps({**good,'page_count':True}), json.dumps(good)+' private',
                  '{"page_count":1,"page_count":2}', 'fixture-secret']
        for value in variants:
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                self.run_fault('import sys;sys.stderr.write("fixture-token");print('+repr(value)+')')
        with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
            self.run_fault('import sys;print("fixture-token",file=sys.stderr);sys.exit(2)')

    def test_infinite_stdout_is_capped_and_stall_is_killed_and_reaped(self):
        processes=[]
        original=worker.subprocess.Popen
        def track(*args, **kwargs):
            p=original(*args, **kwargs);processes.append(p);return p
        with patch.object(worker.subprocess, 'Popen', side_effect=track):
            for code in ('import os;\nwhile True: os.write(1,b"x"*8192)',
                         'import time;time.sleep(30)'):
                with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                    self.run_fault(code)
        self.assertEqual(len(processes), 2)
        for p in processes:
            self.assertIsNotNone(p.returncode)
            with self.assertRaises(ChildProcessError):
                os.waitpid(p.pid, os.WNOHANG)

    def test_exited_leader_and_surviving_owned_group_are_cleaned_up(self):
        result={'candidate_policy':worker.POLICY,'pdf_sha256':self.digest,
                'page_count':1,'text_sha256':'a'*64}
        for close_output in (False, True):
            with self.subTest(close_output=close_output), tempfile.TemporaryDirectory() as root:
                pidfile=Path(root)/'descendant.pid'
                code=f"""import os,time
pid=os.fork()
if pid==0:
 open({str(pidfile)!r},'w').write(str(os.getpid()))
 if {close_output!r}: os.close(1);os.close(2)
 time.sleep(30)
 os._exit(0)
for _ in range(200):
 if os.path.exists({str(pidfile)!r}): break
 time.sleep(.005)
os.write(1,{json.dumps(result).encode()!r})
os._exit(0)
"""
                if close_output:
                    self.assertEqual(self.run_fault(code, timeout=2)['page_count'], 1)
                else:
                    with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                        self.run_fault(code, timeout=1)
                pid=int(pidfile.read_text())
                status=Path(f'/proc/{pid}/stat')
                # Killed grandchildren may await host init reaping; they must
                # never remain executing. Only our direct child is reaped here.
                def state():
                    try:
                        return status.read_text().split()[2]
                    except FileNotFoundError:
                        return None
                end=time.monotonic()+2
                observed=state()
                while observed not in (None, 'Z') and time.monotonic()<end:
                    time.sleep(.01);observed=state()
                self.assertIn(observed, (None, 'Z'))

    def test_real_child_enforces_limits_at_parser_import(self):
        module_dir=str(Path(worker.__file__).resolve().parent)
        code=f"""import sys,resource
sys.path.insert(0,{module_dir!r})
import inspection_worker_candidate as worker
class Hook:
 def find_spec(self, fullname, path=None, target=None):
  if fullname=='inspect_pdf_candidate':
   for kind,limit in [(resource.RLIMIT_AS,512*1024*1024),(resource.RLIMIT_CPU,3),(resource.RLIMIT_FSIZE,0),(resource.RLIMIT_CORE,0),(resource.RLIMIT_NOFILE,32)]:
    assert resource.getrlimit(kind)==(limit,limit)
  return None
sys.meta_path.insert(0,Hook())
worker._child()
"""
        metadata=worker._metadata(self.pdf,self.digest,'Only Owner',())
        header=json.dumps(metadata).encode()
        with tempfile.TemporaryFile() as source:
            source.write(struct.pack('>I',len(header))+header+self.pdf);source.seek(0)
            result=worker._supervise(source,self.digest,5,[sys.executable,'-I','-c',code])
        self.assertEqual(result['page_count'],1)

    def test_environment_and_unpassed_file_descriptors_are_not_inherited(self):
        with tempfile.TemporaryFile() as private:
            os.set_inheritable(private.fileno(), True)
            code=f'''import os,json
assert 'SKO_FIXTURE_SECRET' not in os.environ
try: os.fstat({private.fileno()})
except OSError: pass
else: raise RuntimeError('inherited descriptor')
print({json.dumps({'candidate_policy':worker.POLICY,'pdf_sha256':self.digest,'page_count':1,'text_sha256':'a'*64})!r})'''
            with patch.dict(os.environ, {'SKO_FIXTURE_SECRET':'fixture-secret'}):
                self.assertEqual(self.run_fault(code, timeout=5)['page_count'], 1)

    def test_admission_is_nonblocking_and_released_after_failure(self):
        self.assertTrue(worker._ADMISSION.acquire(blocking=False))
        self.assertTrue(worker._ADMISSION.acquire(blocking=False))
        try:
            with patch.object(worker.subprocess,'Popen',side_effect=AssertionError('no spawn')):
                with self.assertRaisesRegex(ValueError, '^'+worker.ERROR+'$'):
                    self.observe()
        finally:
            worker._ADMISSION.release();worker._ADMISSION.release()
        with self.assertRaises(ValueError):
            self.observe(expected_owner='Foreign Owner')
        self.assertEqual(self.observe()['page_count'], 1)

    def test_child_limits_are_applied_before_pdf_import(self):
        # Structural ordering check; the real-parser tests separately run a child.
        import resource
        expected={resource.RLIMIT_AS:512*1024*1024,resource.RLIMIT_CPU:3,
                  resource.RLIMIT_FSIZE:0,resource.RLIMIT_CORE:0,resource.RLIMIT_NOFILE:32}
        seen=[]
        with patch.object(resource,'setrlimit',side_effect=lambda k,v:seen.append((k,v))), \
             patch.object(sys,'stdin',type('Input',(),{'buffer':io.BytesIO(b'')})()):
            with self.assertRaises(ValueError):
                worker._child()
        self.assertEqual(seen, [(k,(v,v)) for k,v in expected.items()])


if __name__=='__main__':
    unittest.main()
