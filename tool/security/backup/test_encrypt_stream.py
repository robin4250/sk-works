import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('encrypt_stream.py')
DATA = b'SYNTHETIC ONLY: salary=12345; bank=fixture; credential=fixture\n' * 100


class EncryptionTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='sko-backup-fixture-')
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.identity = self.root / 'fixture.identity'
        subprocess.run(['age-keygen', '-o', str(self.identity)], check=True, capture_output=True)
        self.public = self.root / 'recipient.txt'
        self.public.write_bytes(subprocess.check_output(['age-keygen', '-y', str(self.identity)]))
        self.output = self.root / 'backup.age'

    def run_encryption(self):
        return subprocess.run([sys.executable, str(SCRIPT), '--recipient-file', str(self.public),
                               '--output', str(self.output)], input=DATA, capture_output=True)

    def test_actual_encryption_roundtrip_and_private_permissions(self):
        result = self.run_encryption()
        self.assertEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)['restoration_verified'])
        self.assertNotIn(b'salary=', self.output.read_bytes())
        self.assertNotIn(b'salary=', result.stdout + result.stderr)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        restored = subprocess.check_output(['age', '--decrypt', '-i', str(self.identity), str(self.output)])
        self.assertEqual(restored, DATA)
        self.assertEqual(list(self.root.glob('.sko-encrypted-*')), [])

    def test_wrong_identity_and_modified_ciphertext_cannot_restore(self):
        self.assertEqual(self.run_encryption().returncode, 0)
        wrong = self.root / 'wrong.identity'
        subprocess.run(['age-keygen', '-o', str(wrong)], check=True, capture_output=True)
        rejected = subprocess.run(['age', '--decrypt', '-i', str(wrong), str(self.output)], capture_output=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(rejected.stdout, b'')
        altered = bytearray(self.output.read_bytes())
        altered[-1] ^= 1
        self.output.write_bytes(altered)
        rejected = subprocess.run(['age', '--decrypt', '-i', str(self.identity), str(self.output)], capture_output=True)
        self.assertNotEqual(rejected.returncode, 0)

    def test_existing_destination_is_preserved(self):
        self.output.write_bytes(b'previous-backup')
        self.assertNotEqual(self.run_encryption().returncode, 0)
        self.assertEqual(self.output.read_bytes(), b'previous-backup')

    def test_private_key_cannot_be_used_as_public_recipient(self):
        shutil.copyfile(self.identity, self.public)
        result = self.run_encryption()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertNotIn(b'AGE-SECRET-KEY', result.stdout + result.stderr)

    def test_invalid_recipient_leaves_no_partial_backup(self):
        self.public.write_text('age1' + 'q' * 58)
        self.assertNotEqual(self.run_encryption().returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob('.sko-encrypted-*')), [])


if __name__ == '__main__':
    unittest.main()
