import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from save_receipt import save_receipt

class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'receipts'
        self.payload = dict(scope='GLOBAL exemption management only',phase='prepared',
            artifact_sha256='a'*64,evidence_sha256='b'*64,approval_reference=None,
            production_applied=False)

    def test_exclusive_no_overwrite(self):
        a=save_receipt(self.directory,self.payload,receipt_id='abc')
        before=Path(a['receipt']).read_bytes()
        with self.assertRaises(FileExistsError):
            save_receipt(self.directory,{**self.payload,'scope':'changed'},receipt_id='abc')
        self.assertEqual(Path(a['receipt']).read_bytes(),before)
        self.assertEqual(a['sha256'],hashlib.sha256(before).hexdigest())
        self.assertEqual(os.stat(a['receipt']).st_mode & 0o777,0o600)
        self.assertFalse(list(self.directory.glob('.pending-*')))

    def test_concurrent_append(self):
        self.directory.mkdir(mode=0o700)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            results=list(executor.map(lambda _:save_receipt(self.directory,self.payload),range(24)))
        self.assertEqual(len({r['receipt'] for r in results}),24)
        for r in results:
            self.assertEqual(json.loads(Path(r['receipt']).read_text()),self.payload)

    def test_symlink_and_unsafe_permissions_rejected(self):
        real=Path(self.temp.name)/'real';real.mkdir(mode=0o700)
        self.directory.symlink_to(real,target_is_directory=True)
        with self.assertRaises(ValueError):save_receipt(self.directory,self.payload)
        self.directory.unlink();self.directory.mkdir(mode=0o755)
        with self.assertRaises(ValueError):save_receipt(self.directory,self.payload)

    def test_approval_required_for_application_evidence(self):
        with self.assertRaises(ValueError):
            save_receipt(self.directory,{**self.payload,'phase':'commit_confirmed'})
        result=save_receipt(self.directory,{**self.payload,'phase':'commit_unknown','approval_reference':'synthetic-test-only'})
        self.assertEqual(json.loads(Path(result['receipt']).read_text())['phase'],'commit_unknown')

if __name__=='__main__':unittest.main()
