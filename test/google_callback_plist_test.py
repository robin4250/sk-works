"""Execute the exact prepare_ios callback block against synthetic plists only."""
from pathlib import Path
import unittest

source = Path('tool/prepare_ios.sh').read_text()
block = source.split('# Existing Supabase OAuth allowlist uses this scheme, not the Bundle ID.\n', 1)[1].split('# Runtime keeps normal iPhone pages portrait;', 1)[0]
class CallbackPlist(unittest.TestCase):
    def apply(self, data):
        exec(block, {'data': data})
    def test_preserves_and_idempotent(self):
        old = {'CFBundleURLName':'old', 'CFBundleURLSchemes':['old-one','old-two'], 'other':'preserved'}
        data = {'CFBundleURLTypes':[old.copy()], 'CFBundleIdentifier':'com.skworks.skWorks', 'untouched':42}
        self.apply(data)
        self.assertEqual(data['CFBundleURLTypes'][0],old)
        self.assertEqual(data['CFBundleURLTypes'][1]['CFBundleURLSchemes'],['com.skworks.sko'])
        snapshot=repr(data)
        self.apply(data)
        self.assertEqual(repr(data),snapshot)
        self.assertEqual(data['CFBundleIdentifier'],'com.skworks.skWorks')
        self.assertEqual(data['untouched'],42)
    def test_existing_callback_preserved(self):
        data={'CFBundleURLTypes':[{'CFBundleURLSchemes':['old','com.skworks.sko'],'extra':True}]}
        snapshot=repr(data); self.apply(data); self.assertEqual(repr(data),snapshot)
    def test_malformed_refused_without_mutation(self):
        for value in ({},[1],[{'CFBundleURLSchemes':'bad'}],[{'CFBundleURLSchemes':[1]}]):
            data={'CFBundleURLTypes':value}; snapshot=repr(data)
            with self.assertRaises(SystemExit): self.apply(data)
            self.assertEqual(repr(data),snapshot)
if __name__=='__main__': unittest.main()
