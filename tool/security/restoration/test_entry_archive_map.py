import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('mapping',Path(__file__).with_name('entry_archive_map.py'))
mapping=importlib.util.module_from_spec(spec);spec.loader.exec_module(mapping)

ROOTS='''1; 1259 100 TABLE public worker_personnel_profiles postgres
2; 1259 101 TABLE public worker_family_members postgres
3; 1255 102 FUNCTION private employee_personnel_rows(uuid) postgres
4; 1255 103 FUNCTION public can_edit_worker_personnel(uuid) postgres
'''

class MapTests(unittest.TestCase):
    def test_data_and_other_objects_never_selected(self):
        text=ROOTS+'5; 0 100 TABLE DATA public worker_personnel_profiles postgres\n6; 0 0 EXTENSION - pgcrypto postgres\n7; 0 0 TRIGGER public worker_personnel_profiles dangerous postgres\n8; 0 0 TABLE auth users postgres\n'
        selected,report=mapping.classify(text)
        self.assertEqual(len(selected),4);self.assertEqual(report['missing_roots'],[])
        self.assertEqual(report['extension_entry_count'],1)
        self.assertFalse(report['dependencies_complete']);self.assertFalse(report['restoration_verified'])

    def test_extension_without_owner_is_catalogued_not_selected(self):
        selected,r=mapping.classify(ROOTS+'6; 3079 16384 EXTENSION - pgcrypto\n')
        self.assertEqual(len(selected),4);self.assertEqual(r['extension_entry_count'],1)

    def test_duplicate_or_overloaded_function_is_not_guessed(self):
        with self.assertRaises(ValueError):mapping.classify(ROOTS+'9; 1255 104 FUNCTION private employee_personnel_rows(text) postgres\n')

    def test_wrong_schema_is_not_silently_selected(self):
        with self.assertRaises(ValueError):mapping.classify(ROOTS.replace('FUNCTION private employee','FUNCTION public employee'))

    def test_all_toc_ids_must_be_unique(self):
        for line in ('1; 0 0 TABLE DATA public other postgres','3; 0 0 EXTENSION - pgcrypto'):
            with self.assertRaises(ValueError):mapping.classify(ROOTS+line+'\n')

    def test_root_function_signature_required(self):
        for malformed in ('employee_personnel_rows','employee_personnel_rows(uuid','employee_personnel_rows)'):
            with self.assertRaises(ValueError):mapping.classify(ROOTS.replace('employee_personnel_rows(uuid)',malformed))

    def test_missing_roots_are_explicit(self):
        _,r=mapping.classify('1; 1259 100 TABLE public worker_personnel_profiles postgres\n')
        self.assertEqual(len(r['missing_roots']),3)

    def test_unknown_toc_type_requires_further_review(self):
        _,r=mapping.classify(ROOTS+'10; 0 0 SOMETHING NEW public object postgres\n')
        self.assertEqual(r['unrecognized_entry_count'],1)

    def test_malformed_toc_is_rejected(self):
        for text in ['not a toc','1; x y TABLE public x postgres','1; 0 0 TABLE public']:
            with self.assertRaises(ValueError):mapping.classify(text)

if __name__=='__main__':unittest.main()
