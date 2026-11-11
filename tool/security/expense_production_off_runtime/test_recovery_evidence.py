"""New marker-evidence lifecycle boundaries only; no database or production adapter."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from review_runner import FILES, MARKER, Refused, install_review_once, recover_review_readonly, sha


class RecoveryEvidenceTest(unittest.TestCase):
    def test_new_observation_invalidates_previous_undo_reference_without_deleting_evidence(self):
        for outcome in ('before', 'drift', 'read_failure', 'verify_failure'):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary);root.chmod(0o700)
                original=root/'original';original.mkdir(mode=0o700)
                artifacts={}
                for name in FILES:
                    path=original/name;path.write_bytes(b'fixture');path.chmod(0o600)
                    artifacts[name]=sha(b'fixture')
                old=root/'old-unused-undo.sql.review-only';old.write_bytes(b'historical undo');old.chmod(0o600)
                state={'schema':1,'stage':str(original),'artifacts':artifacts,
                    'phase':'installed_off_unused_undo_candidate','retry_allowed':False,
                    'unused_undo':str(old),'unused_undo_sha256':sha(old.read_bytes()),'observation':'old'}
                marker=root/MARKER;marker.write_text(json.dumps(state));marker.chmod(0o600)
                class Transport:
                    reads=0
                    def capture_readonly(self, sql):
                        self.reads+=1
                        if outcome=='read_failure':raise ConnectionError('synthetic')
                        return b'{}'
                    def execute_install_once(self, sql):
                        raise AssertionError('recovery must never submit install')
                transport=Transport()
                def generator(node, stage, mode):
                    if outcome=='verify_failure':raise Refused('synthetic_verify_failure')
                    if mode=='classify':
                        if outcome=='drift':raise Refused('synthetic_drift')
                        path=stage/'classification.json'
                        path.write_text(json.dumps({'state':'before_state_observed'}));path.chmod(0o600)
                with patch('review_runner.generator',side_effect=generator):
                    if outcome=='verify_failure':
                        with self.assertRaises(Refused):recover_review_readonly(root,transport,'node')
                    else:recover_review_readonly(root,transport,'node')
                current=json.loads(marker.read_text())
                self.assertNotIn('unused_undo',current)
                self.assertNotIn('unused_undo_sha256',current)
                self.assertNotEqual(current.get('observation'),'old')
                self.assertFalse(current['retry_allowed'])
                self.assertEqual(old.read_bytes(),b'historical undo')
                expected='before_state_observed' if outcome=='before' else 'read_only_classification_pending' if outcome=='verify_failure' else 'state_requires_review'
                self.assertEqual(current['phase'],expected)
                with self.assertRaisesRegex(Refused,'previous_attempt'):
                    install_review_once(original,root,transport,'node')


if __name__=='__main__':unittest.main()
