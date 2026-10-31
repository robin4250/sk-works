import copy
import importlib.util
import json
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('baseline_builder', HERE / 'build_review.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class BaselineReview(unittest.TestCase):
    def test_only_verbatim_consent_and_actor(self):
        fragments = builder.prepare()
        self.assertEqual(len(fragments), 2)
        consent = fragments['canonical-consent.sql.review-only']
        self.assertEqual(consent, (builder.ROOT / 'docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only').read_text())
        actor = fragments['actor-only.sql.review-only']
        self.assertEqual(actor.count('create function '), 1)
        self.assertNotIn('public.', actor)
        for forbidden in ('parent_links', 'create table', 'scope(', 'resolve(', 'grant execute'):
            self.assertNotIn(forbidden, actor.lower())
        self.assertIn('from public,anon,authenticated,service_role', actor)

    def test_source_drift_rejected(self):
        manifest = json.loads((HERE / 'manifest.json').read_text())
        changed = copy.deepcopy(manifest)
        changed['sources'][next(iter(changed['sources']))] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'canonical source changed'):
            builder.prepare(manifest=changed)

    def test_actor_drift_rejected(self):
        manifest = json.loads((HERE / 'manifest.json').read_text())
        manifest['actor_statement_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'actor exact statement changed'):
            builder.prepare(manifest=manifest)

    def test_real_helper_inventory_not_fixture(self):
        manifest = json.loads((HERE / 'manifest.json').read_text())
        contracts = {x['signature']: x for x in manifest['existing_function_contracts']}
        self.assertEqual(len(contracts), 8)
        self.assertEqual(contracts['private.require_reauthentication_session()']['source_md5'], 'b5c8e2f259a99b3c69694ad0640080e5')
        self.assertFalse(contracts['private.uploaded_company_seal_snapshot(uuid)']['security_definer'])
        self.assertEqual(manifest['status'], 'review-only-not-install-ready')
        self.assertGreater(len(manifest['remaining_gate']), 0)


if __name__ == '__main__':
    unittest.main()
