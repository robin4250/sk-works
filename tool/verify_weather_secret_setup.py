#!/usr/bin/env python3
"""Exercise private terminal entry against a disposable fake Supabase CLI."""
import json
import os
from pathlib import Path
import pty
import select
import tempfile
import time
import unittest

SCRIPT = Path(__file__).with_name('configure_weather_secrets.sh').resolve()
GOOGLE = 'SyntheticGoogleKey_1234567890'
OPENWEATHER = 'SyntheticOpenWeatherKey_1234567890'
MOCK = '''#!/usr/bin/env python3
import json, os, pathlib, stat, sys
args=sys.argv[1:]
if args[:2]==['secrets','list']:
 sys.exit(1 if os.environ['MOCK_MODE']=='unauthenticated' else 0)
assert args[:2]==['secrets','set']
assert args[args.index('--project-ref')+1]=='ztktgquxvcxcjxtluspu'
path=pathlib.Path(args[args.index('--env-file')+1])
values=dict(line.split('=',1) for line in path.read_text().splitlines())
assert values=={'WEATHER_GEOCODING_PROVIDER':'google','WEATHER_GEOCODING_API_KEY':'SyntheticGoogleKey_1234567890','OPENWEATHER_API_KEY':'SyntheticOpenWeatherKey_1234567890'}
assert stat.S_IMODE(path.stat().st_mode)==0o600
assert stat.S_IMODE(path.parent.stat().st_mode)==0o700
assert not any('Synthetic' in arg for arg in args)
pathlib.Path(os.environ['MOCK_CAPTURE']).write_text(json.dumps({'directory':str(path.parent),'private':True}))
if os.environ['MOCK_MODE']=='failed':
 print('SyntheticGoogleKey_1234567890',file=sys.stderr)
 sys.exit(1)
'''

class SetupTest(unittest.TestCase):
 def run_setup(self, mode='success', invalid=False):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp); binary=root/'supabase'; binary.write_text(MOCK); binary.chmod(0o755)
   capture=root/'capture.json'
   pid, fd=pty.fork()
   if pid==0:
    os.environ.update(PATH=str(root)+os.pathsep+os.environ['PATH'],MOCK_MODE=mode,MOCK_CAPTURE=str(capture),TMPDIR=str(root))
    os.execv('/bin/bash',['bash',str(SCRIPT)])
   output=b''; sent_google=sent_openweather=False; status=None
   try:
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
     ready,_,_=select.select([fd],[],[],0.1)
     if ready:
      try: chunk=os.read(fd,8192)
      except OSError: break
      if not chunk: break
      output+=chunk
      if b'Time Zone API' in output and not sent_google:
       os.write(fd,('invalid' if invalid else GOOGLE).encode()+b'\n');sent_google=True
      if b'One Call 3.0 API' in output and not sent_openweather:
       os.write(fd,OPENWEATHER.encode()+b'\n');sent_openweather=True
     ended, observed=os.waitpid(pid,os.WNOHANG)
     if ended: status=observed;break
    if status is None:
     ended,status=os.waitpid(pid,os.WNOHANG)
     if not ended:
      os.kill(pid,9);os.waitpid(pid,0);self.fail('terminal setup timed out')
   finally: os.close(fd)
   self.assertNotIn(GOOGLE.encode(),output)
   self.assertNotIn(OPENWEATHER.encode(),output)
   if capture.exists():
    self.assertFalse(Path(json.loads(capture.read_text())['directory']).exists())
   self.assertFalse(list(root.glob('sko-weather-secrets.*')))
   return os.waitstatus_to_exitcode(status), output, capture.exists()
 def test_private_registration_and_cleanup(self):
  code,_,registered=self.run_setup();self.assertEqual(code,0);self.assertTrue(registered)
 def test_backend_error_does_not_echo_key_and_cleans_file(self):
  code,_,registered=self.run_setup('failed');self.assertNotEqual(code,0);self.assertTrue(registered)
 def test_invalid_key_never_calls_set(self):
  code,_,registered=self.run_setup(invalid=True);self.assertNotEqual(code,0);self.assertFalse(registered)
 def test_authentication_required_before_key_entry(self):
  code,output,registered=self.run_setup('unauthenticated');self.assertNotEqual(code,0);self.assertFalse(registered);self.assertNotIn(b'One Call',output)

if __name__=='__main__': unittest.main()
