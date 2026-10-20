import base64
import os
import ipaddress
import shutil
import contextlib
import hashlib
import hmac
import http.server
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
sys.path.append(str(Path(__file__).parents[1]/'payroll-common-native-rehearsal-20261020'))
import owner_common_http_rehearsal as probe


class Handler(http.server.BaseHTTPRequestHandler):
    seen=[]
    def do_GET(self):
        if self.path=='/redirect':
            self.send_response(302);self.send_header('Location','https://unreachable.invalid/not-permitted');self.end_headers();return
        self.send_response(200);self.end_headers()
        self.wfile.write(b'x'*(1048577) if self.path=='/oversize' else b'{"fixture":true}')
    def do_POST(self):
        raw=self.rfile.read(int(self.headers.get('Content-Length','0')))
        self.seen.append({'authorization':self.headers.get('Authorization'),'json':json.loads(raw)})
        self.send_response(403);self.end_headers();self.wfile.write(b'{"code":"42501"}')
    def log_message(self,*args): pass


class CommonHttpTests(unittest.TestCase):
    def test_local_http_auth_body_error_and_no_secret_logging(self):
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            api=probe.InternalCurlHttp('sko-http-db-'+'a'*12,dict.fromkeys(('auth','rest'),'http://127.0.0.1:'+str(server.server_port)),os.environ.copy())
            real=probe.bounded_http_exec
            def local(args,data,env):
                self.assertEqual(args[:4],['docker','exec','-i','sko-http-db-'+'a'*12])
                self.assertNotIn('synthetic-password',str(args))
                return real(args[4:],data,env)
            transport=patch.object(probe,'bounded_http_exec',side_effect=local);transport.start();self.addCleanup(transport.stop)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                status,data=api.call('auth','/token?grant_type=password','synthetic-bearer',{'password':'synthetic-password', 'unicode':'日本語', 'escape':'quote" newline\n slash\\'})
            self.assertEqual(status,403);self.assertEqual(data,{'code':'42501'})
            self.assertEqual(Handler.seen[-1]['authorization'],'Bearer synthetic-bearer')
            self.assertEqual(Handler.seen[-1]['json']['password'],'synthetic-password')
            self.assertEqual(output.getvalue(),'')
            self.assertEqual(api.call('auth','/health',method='GET'),(200,{'fixture':True}))
            with self.assertRaisesRegex(RuntimeError,'redirect_refused'):api.call('auth','/redirect',method='GET')
            with self.assertRaises(RuntimeError):api.call('auth','/oversize',method='GET')
        finally:server.shutdown();server.server_close();thread.join()

    def test_only_locally_signed_service_bootstrap_token(self):
        token=probe.jwt('synthetic-secret','service_role');header,payload,sig=token.split('.')
        self.assertEqual(json.loads(base64.urlsafe_b64decode(header+'===')),{'alg':'HS256','typ':'JWT'})
        claims=json.loads(base64.urlsafe_b64decode(payload+'==='));self.assertEqual(claims['role'],'service_role')
        self.assertEqual(claims['exp']-claims['iat'],3600)
        expected=base64.urlsafe_b64encode(hmac.new(b'synthetic-secret',(header+'.'+payload).encode(),hashlib.sha256).digest()).decode().rstrip('=')
        self.assertEqual(sig,expected)

    def test_identity_fingerprint_exclusion_is_uuid_only(self):
        text=probe.identity_sql(['00000000-0000-0000-0000-000000000001'])
        self.assertIn("id NOT IN ('00000000-0000-0000-0000-000000000001')",text)
        self.assertNotIn('UPDATE ',text);self.assertNotIn('DELETE ',text)
        with self.assertRaises(ValueError):probe.identity_sql(["bad');drop table auth.users;--"])

    def test_commit_is_only_for_clone_and_builder_is_reused(self):
        with patch.object(probe.common,'build_install',return_value='BEGIN;SELECT 1;\nROLLBACK;'):
            self.assertEqual(probe.commit_install({}),'BEGIN;SELECT 1;\nCOMMIT;')
        with patch.object(probe.common,'build_install',return_value='unknown transaction'):
            with self.assertRaisesRegex(RuntimeError,'shape_changed'):probe.commit_install({})

    def test_required_images_and_internal_clone_profile(self):
        for image in (probe.AUTH_IMAGE,probe.REST_IMAGE):
            self.assertRegex(image,r'^[a-z/]+@sha256:[a-f0-9]{64}$')
            probe.image_check({'RepoDigests':[image],'Os':'linux','Architecture':'arm64'},image)
            with self.assertRaisesRegex(RuntimeError,'digest_missing'):probe.image_check({'RepoDigests':[]},image)
        args=probe.clone_command('fixture','sha256:'+'a'*64,'internal-fixture')
        self.assertIn('--network=internal-fixture',args);self.assertIn('--log-driver=none',args)
        self.assertIn('cron.launch_active_jobs=off',args);self.assertIn('listen_addresses=*',args)
        for key in ('--publish','--privileged','--mount','-p'):self.assertNotIn(key,args)

    def test_missing_image_refuses_before_network_and_original_start_stop(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);root=home/'SKO-source-backups';root.mkdir(mode=0o700)
            source=root/probe.common.transport.SOURCE;source.mkdir(mode=0o700)
            original='sko-restore-'+'b'*12
            (source/'rehearsal-status.json').write_text(json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':original}))
            calls=[]
            def run(args,**kwargs):
                calls.append(args);output=b'';code=0
                if args[:3]==['docker','context','inspect']:output=json.dumps([{'Endpoints':{'docker':{'Host':'unix:///synthetic'}}}]).encode()
                elif args[:2]==['docker','inspect']:output=json.dumps([{'State':{'Running':False},'HostConfig':{'NetworkMode':'none','PortBindings':{}},'Config':{'Image':probe.common.transport.BASE_IMAGE,'Labels':{'sko-purpose':'offline-restore'}}}]).encode()
                elif args[:3]==['docker','image','inspect']:code=1
                return subprocess.CompletedProcess(args,code,output,b'')
            with patch.object(probe.sys,'platform','darwin'),patch.object(probe.Path,'home',return_value=home),patch.dict(probe.os.environ,{},clear=True),patch.object(probe.subprocess,'run',side_effect=run),patch.object(probe,'commit_install',return_value='safe clone-only SQL'),patch.object(probe.Path,'read_text',lambda p:json.dumps({}) if p.name=='common_payroll_sources.json' else json.dumps({'archive_restore_verified':True,'container_stopped':True,'container':original})),contextlib.redirect_stdout(io.StringIO()):
                code=probe.main()
            self.assertEqual(code,1)
            self.assertFalse(any(args[:3]==['docker','network','create'] for args in calls))
            self.assertFalse(any(args[:2] in (['docker','start'],['docker','stop'],['docker','rm']) and original in args for args in calls))
            self.assertTrue(any(args==['/usr/bin/pbcopy'] for args in calls))


    def test_bounded_process_timeout_and_size(self):
        with self.assertRaisesRegex(RuntimeError,'timeout'):
            probe.bounded_http_exec([sys.executable,'-c','import time;time.sleep(10)'],b'x',os.environ.copy(),timeout=.1)
        with self.assertRaisesRegex(RuntimeError,'too_large'):
            probe.bounded_http_exec([sys.executable,'-c','import sys;sys.stdout.write("x"*1100000)'],b'x',os.environ.copy())
        with self.assertRaisesRegex(RuntimeError,'client_failed'):
            probe.bounded_http_exec([sys.executable,'-c','import sys;sys.exit(7)'],b'x',os.environ.copy())

    def test_internal_endpoint_requires_no_host_ports_and_exact_network(self):
        info={'NetworkSettings':{'Networks':{'fixture':{'IPAddress':'172.29.1.3'}}},'HostConfig':{'LogConfig':{'Type':'none'},'PortBindings':{}},'State':{'Running':True},'Config':{'Image':probe.AUTH_IMAGE}}
        subnet=ipaddress.ip_network('172.29.1.0/24')
        self.assertEqual(probe.internal_endpoint(info,9999,'fixture',subnet,probe.AUTH_IMAGE),'http://172.29.1.3:9999')
        info['HostConfig']['PortBindings']={'9999/tcp':[]}
        with self.assertRaisesRegex(RuntimeError,'host_publish_forbidden'):probe.internal_endpoint(info,9999,'fixture',subnet,probe.AUTH_IMAGE)
        info['HostConfig']['PortBindings']={};info['NetworkSettings']['Networks']['fixture']['IPAddress']='127.0.0.1'
        with self.assertRaisesRegex(RuntimeError,'service_ip_not_internal'):probe.internal_endpoint(info,9999,'fixture',subnet,probe.AUTH_IMAGE)

    def test_request_config_rejects_injection(self):
        api=probe.InternalCurlHttp('sko-http-db-'+'a'*12,dict.fromkeys(('auth','rest'),'http://172.29.1.3:9999'),{})
        for path in ('//outside.invalid','https://outside.invalid','/x\r\nHost: evil'):
            with self.assertRaisesRegex(RuntimeError,'route_invalid'):api.config('auth',path,None,None,'GET',None)
        with self.assertRaisesRegex(RuntimeError,'token_invalid'):api.config('auth','/', 'x\nurl = evil',None,'GET',None)
        with self.assertRaisesRegex(RuntimeError,'header_invalid'):api.config('auth','/',None,None,'GET',{'Host':'outside.invalid'})

if __name__=='__main__':unittest.main()
