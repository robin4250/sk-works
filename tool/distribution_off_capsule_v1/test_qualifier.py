"""Synthetic metadata only; no production identities, URLs, rows or network."""
import copy
import os
from pathlib import Path
import unittest

from qualifier import PROFILES, PREDICATES, Rejected, qualify

EXISTING = next(i for i, row in enumerate(PROFILES) if row['exists'])
ABSENT = next(i for i, row in enumerate(PROFILES) if not row['exists'])


def fixture():
    rows = copy.deepcopy(PROFILES)
    role_oids = {'postgres': 10, 'authenticated': 20, 'service_role': 30}
    for index, row in enumerate(rows):
        row.update(oid=1000 + index if row['exists'] else None,
                   schema_oid=100 if row['exists'] else None,
                   owner_oid=10 if row['exists'] else None)
        if row['acl'] is not None:
            for acl in row['acl']:
                acl.update(grantee_oid=role_oids[acl['grantee']], grantor_oid=10)
    return dict(baseline=copy.deepcopy(rows), current=copy.deepcopy(rows),
                overloads=[r['signature'] for r in rows if r['exists']],
                settings={key: True for key in PREDICATES},
                preservation_reference=dict(sha256='a' * 64,
                    scope='private-before-post-settings-history-dependencies', verified=False))


class QualifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(os.environ.get('DISTRIBUTION_TEST_SOURCE_ROOT', Path(__file__).resolve().parents[2]))
        cls.installer = (root / 'docs/candidates/app_distribution_off_install_20261020.sql.review-only').read_bytes()

    def rejected(self, change, reason=None):
        value = fixture()
        change(value)
        with self.assertRaises(Rejected) as caught:
            qualify(self.installer, value)
        if reason:
            self.assertEqual(str(caught.exception), reason)

    def test_review_only_even_when_synthetic_metadata_matches(self):
        value = fixture()
        output = qualify(self.installer, value)
        self.assertIs(output['deployable'], False)
        self.assertIs(output['approval'], False)
        self.assertIsNone(output['execution'])
        self.assertIsNone(output['sql'])
        self.assertEqual(len(output['post_allowlist']['create_functions']), 5)
        self.assertEqual(len(output['post_allowlist']['create_tables']), 2)
        self.assertIn('private preservation anchor contents unverified', output['blocked'])
        value['current'][EXISTING]['oid'] = 999
        self.assertNotEqual(value['current'], output['before']['current'])

    def test_all_four_settings_required_and_exact_booleans(self):
        for key in PREDICATES:
            for bad in (False, None, 0, 1, 'true'):
                with self.subTest(key=key, bad=bad):
                    self.rejected(lambda x: x['settings'].__setitem__(key, bad))
            self.rejected(lambda x: x['settings'].pop(key))
        self.rejected(lambda x: x['settings'].__setitem__('url', 'not-read'))

    def test_missing_extra_duplicate_and_overloads_fail(self):
        self.rejected(lambda x: x.pop('current'))
        self.rejected(lambda x: x.__setitem__('approval', True))
        self.rejected(lambda x: x['current'].pop())
        self.rejected(lambda x: x['current'].__setitem__(ABSENT, copy.deepcopy(x['current'][EXISTING])))
        self.rejected(lambda x: x['overloads'].append('public.app_referral_snapshot(text)'))
        self.rejected(lambda x: x['overloads'].pop())
        self.rejected(lambda x: x['overloads'].append(x['overloads'][0]))

    def test_identity_and_source_drift_are_not_refreshed(self):
        for field, bad in [('oid', 9000), ('owner_oid', 50), ('body_md5', 'f' * 32),
                           ('definition_md5', 'e' * 32), ('security_definer', False),
                           ('settings', ['search_path=public']), ('owner', 'unexpected')]:
            with self.subTest(field=field):
                self.rejected(lambda x: x['current'][EXISTING].__setitem__(field, bad))
        for bad in (None, True, 0, -1, 4294967296, '1000'):
            self.rejected(lambda x: x['current'][EXISTING].__setitem__('oid', bad))
        # Matching forged baseline/current still cannot change source attributes.
        self.rejected(lambda x: [x[k][EXISTING].__setitem__('body_md5', 'f' * 32) for k in ('baseline', 'current')])
        self.rejected(lambda x: x['current'][ABSENT].__setitem__('oid', 8000))

    def test_acl_privileges_roles_and_grant_options_fail(self):
        for field, bad in [('grantee', 'unknown'), ('grantable', True), ('grantable', 0),
                           ('grantor', 'unknown'), ('privilege', 'ALL'), ('grantor_oid', 99)]:
            with self.subTest(field=field):
                self.rejected(lambda x: x['current'][EXISTING]['acl'][0].__setitem__(field, bad))
        self.rejected(lambda x: x['current'][EXISTING]['acl'].append(copy.deepcopy(x['current'][EXISTING]['acl'][0])))
        self.rejected(lambda x: x['current'][EXISTING]['acl'][0].__setitem__('unexpected', 'x'))

    def test_unverified_anchor_cannot_be_promoted_or_omitted(self):
        self.rejected(lambda x: x.__setitem__('preservation_reference', None))
        self.rejected(lambda x: x['preservation_reference'].__setitem__('verified', True))
        self.rejected(lambda x: x['preservation_reference'].__setitem__('sha256', "';drop table x;--"))
        self.rejected(lambda x: x['preservation_reference'].__setitem__('scope', 'fixture'))

    def test_immutable_installer_rejects_any_byte_change(self):
        for body in (b'', self.installer + b'\n', self.installer.replace(b'begin;', b'-- begin;', 1)):
            with self.assertRaisesRegex(Rejected, 'immutable installer hash'):
                qualify(body, fixture())


if __name__ == '__main__':
    unittest.main()
