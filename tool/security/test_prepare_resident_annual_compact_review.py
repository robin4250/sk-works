import unittest
from pathlib import Path
import prepare_resident_annual_compact_review as compact
import prepare_resident_annual_deployment_review as original

ROOT = Path(__file__).resolve().parents[2]


def checkpoint():
    return {'schema': 1,
            'data': {t: {'count': 0, 'sha256': 'fixture'} for t in original.PROTECTED_TABLES},
            'relations': {t: {'owner': 'postgres', 'rls': True} for t in original.PROTECTED_TABLES},
            'routines': {s: {'source_md5': original.PINNED.get(s, 'fixture'), 'definition': 'fixture' * 1000, 'owner': 'postgres', 'attributes': {'prosecdef': True, 'proconfig': ['search_path=""']}} for s in original.DEPENDENCIES},
            'namespaces': {n: {'owner': 'postgres'} for n in original.EXISTING_NAMESPACES}}


class Compact(unittest.TestCase):
    def test_exact_source_and_all_guards_retained(self):
        before = checkpoint()
        sql = compact.prepare_install(before, 'a' * 64, ROOT)
        body, expected = original.sources(ROOT)
        self.assertIn(body, sql)
        self.assertIn(original.new_object_guard(expected), sql)
        self.assertIn(original.lock_tables(original.PROTECTED_TABLES), sql)
        self.assertIn("set local TimeZone='UTC';", sql)
        self.assertIn("set local DateStyle='ISO, YMD';", sql)
        self.assertIn('sha256(convert_to', sql)
        self.assertIn('annual compact inventory differs', sql)
        self.assertNotIn('fixture', sql)
        self.assertLess(len(sql), len(original.prepare_install(before, ROOT)))

    def test_digest_must_be_explicit_valid_hex(self):
        for invalid in ['', 'a' * 63, 'A' * 64, "a' OR true"]:
            with self.assertRaises(ValueError):
                compact.prepare_install(checkpoint(), invalid, ROOT)

    def test_incomplete_original_refused(self):
        before = checkpoint()
        before['data'].pop(original.PROTECTED_TABLES[0])
        with self.assertRaises(ValueError):
            compact.prepare_install(before, 'a' * 64, ROOT)


if __name__ == '__main__':
    unittest.main()
