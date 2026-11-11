"""Offline wrapper boundaries only; no Docker daemon/network/database used."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch
import offline_docker_generator as bridge

class OfflineDockerBridgeTest(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.root.chmod(0o700)
  self.runtime=self.root/'runtime';self.runtime.mkdir(mode=0o700)
  for name in bridge.SOURCE_HASHES:
   path=self.runtime/name;path.parent.mkdir(mode=0o700,exist_ok=True);shutil.copyfile(bridge.RUNTIME/name,path)
  self.stage=self.root/'expense-production-off-review-fixture';self.stage.mkdir(mode=0o700)
  self.docker=self.root/'docker';self.docker.write_text('fixture executable');self.docker.chmod(0o700)
 def tearDown(self):self.tmp.cleanup()
 def arguments(self):return [str(self.runtime/'offline_generator.mjs'),'verify',str(self.stage)]
 def test_fixed_arguments_root_no_external_stage_or_modified_source(self):
  with patch.object(bridge,'RUNTIME',self.runtime):
   self.assertEqual(bridge.validate_args(self.arguments(),self.root),self.stage)
   for args in [self.arguments()+['extra'],[self.arguments()[0],'restore',str(self.stage)],['/other/script','verify',str(self.stage)],[self.arguments()[0],'verify',str(self.root)]]:
    with self.assertRaises(Exception):bridge.validate_args(args,self.root)
   source=self.runtime/'expense_default_off_plan.mjs';source.write_bytes(source.read_bytes()+b'changed')
   with self.assertRaises(Exception):bridge.validate_args(self.arguments(),self.root)
 def test_clean_real_home_local_context_exact_image_and_offline_mounts(self):
  calls=[]
  def run(args,**kw):
   calls.append((args,kw))
   out=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///fixture/docker.sock'}}}]).encode() if args[1]=='context' else json.dumps([{'Id':bridge.IMAGE,'Os':'linux','Architecture':'arm64'}]).encode() if args[1]=='image' else b''
   return subprocess.CompletedProcess(args,0,out,b'')
  with patch.object(bridge,'RUNTIME',self.runtime),patch.object(bridge,'bound_root',return_value=self.root),patch.object(bridge.sys,'platform','darwin'),patch.object(bridge.sys,'argv',['wrapper',*self.arguments()]),patch.object(bridge.shutil,'which',return_value=str(self.docker)),patch.object(bridge.pwd,'getpwuid',return_value=types.SimpleNamespace(pw_dir='/Users/real-owner')),patch.dict(os.environ,{'PATH':'/untrusted','HOME':'/untrusted'},clear=True),patch.object(bridge.subprocess,'run',side_effect=run):
   self.assertEqual(bridge.main(),0)
  self.assertEqual(len(calls),3)
  args,kw=calls[-1]
  self.assertIn('--network=none',args);self.assertIn('--pull=never',args);self.assertIn('--log-driver=none',args);self.assertIn('--read-only',args);self.assertIn(bridge.IMAGE,args)
  self.assertEqual(args[-3:],[str(self.runtime/'offline_generator.mjs'),'verify',str(self.stage)])
  self.assertEqual(sum(a.startswith('type=bind,') for a in args),2)
  for _,kw in calls:
   self.assertEqual(kw['env']['HOME'],'/Users/real-owner');self.assertEqual(kw['env']['PATH'],bridge.SEARCH);self.assertTrue(kw['close_fds']);self.assertNotIn('shell',kw)
 def test_remote_context_wrong_image_or_docker_override_never_runs_container(self):
  for remote,image in [('tcp://remote:2375',bridge.IMAGE),('unix:///fixture/docker.sock','sha256:'+'0'*64)]:
   calls=[]
   def run(args,**kw):
    calls.append(args);out=[{'Endpoints':{'docker':{'Host':remote}}}] if args[1]=='context' else [{'Id':image,'Os':'linux','Architecture':'arm64'}]
    return subprocess.CompletedProcess(args,0,json.dumps(out).encode(),b'')
   with patch.object(bridge,'RUNTIME',self.runtime),patch.object(bridge,'bound_root',return_value=self.root),patch.object(bridge.sys,'platform','darwin'),patch.object(bridge.sys,'argv',['wrapper',*self.arguments()]),patch.object(bridge.shutil,'which',return_value=str(self.docker)),patch.dict(os.environ,{},clear=True),patch.object(bridge.subprocess,'run',side_effect=run):self.assertEqual(bridge.main(),2)
   self.assertFalse(any(a[1]=='run' for a in calls))
  with patch.object(bridge.sys,'platform','darwin'),patch.dict(os.environ,{'DOCKER_HOST':'unix:///override'},clear=True),patch.object(bridge,'bound_root') as bound:self.assertEqual(bridge.main(),2);bound.assert_not_called()

if __name__=='__main__':unittest.main()
