import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('isolation',Path(__file__).with_name('entry_isolation.py'))
isolation=importlib.util.module_from_spec(spec);spec.loader.exec_module(isolation)


class IsolationTests(unittest.TestCase):
    def test_no_probe_is_inert(self):
        with patch.object(sys,'argv',['probe']),patch.object(isolation.socket,'socket') as sockets,patch.object(isolation.subprocess,'run') as run,contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(isolation.main(),2)
        sockets.assert_not_called();run.assert_not_called()

    def test_unsupported_platform_never_falls_back(self):
        with patch.object(sys,'argv',['probe','--probe']),patch.object(sys,'platform','linux'),patch.object(isolation.socket,'socket') as sockets,patch.object(isolation.subprocess,'run') as run,contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(isolation.main(),1)
        self.assertIn('no fallback',output.getvalue());sockets.assert_not_called();run.assert_not_called()

    def test_profile_has_no_ip_outbound_or_broad_write_exception(self):
        text=isolation.profile(Path('/private/example'),Path('/private/example/only.sock'))
        self.assertIn('(deny default)',text);self.assertIn('(deny network*)',text)
        self.assertNotIn('remote ip',text)
        self.assertEqual(text.count('(allow file-write*'),1)
        self.assertIn('(remote unix-socket (literal "/private/example/only.sock"))',text)
        with self.assertRaises(ValueError):isolation.profile(Path('/private/example'),Path('/elsewhere/only.sock'))
        with self.assertRaises(ValueError):isolation.quote('/private/unsafe\npath')

    def test_strict_probe_result_not_truthiness(self):
        data={k:True for k in ('inside_write','outside_write_denied','ipv4_outbound_denied','ipv6_outbound_denied','unix_socket_success')}
        isolation.require_result(data)
        for value in (False,1,'true',None):
            candidate=dict(data,ipv6_outbound_denied=value)
            with self.assertRaises(ValueError):isolation.require_result(candidate)
        with self.assertRaises(ValueError):isolation.require_result(dict(data,additional=True))


if __name__=='__main__':unittest.main()
