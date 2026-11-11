#!/usr/bin/env python3
"""Synthetic macOS kernel probe only. Never starts PostgreSQL or executes SQL.

Profile construction follows SwiftPM Sources/Basics/Sandbox.swift. A successful
probe is not a complete restoration security proof or permission to restore.
"""
import argparse
import errno
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading


def quote(value):
    if any(ord(c) < 32 for c in str(value)):
        raise ValueError('control characters in path')
    return '"' + str(value).replace('\\','\\\\').replace('"','\\"') + '"'


def profile(inside, unix):
    if not inside.is_absolute() or not unix.is_absolute() or unix.parent != inside:
        raise ValueError('fixed private socket boundary required')
    return ('(version 1)\n(deny default)\n(import "system.sb")\n'
            '(allow file-read*)\n(allow process*)\n(deny network*)\n'
            '(allow file-write* (subpath ' + quote(inside) + '))\n'
            '(allow network-outbound (remote unix-socket (literal ' + quote(unix) + ')))\n'
            '(allow network-inbound (local unix-socket (literal ' + quote(unix) + ')))\n')


CHILD = r'''
import errno,json,pathlib,socket,sys
inside, outside, unix, port4, port6 = sys.argv[1:]
result={}
pathlib.Path(inside,'inside.txt').write_text('synthetic-only')
result['inside_write']=True
try:
 pathlib.Path(outside).write_text('must-not-change')
 result['outside_write_denied']=False
except OSError as e:
 result['outside_write_denied']=e.errno in (errno.EPERM,errno.EACCES)
for label,family,host,port in [('ipv4',socket.AF_INET,'127.0.0.1',port4),('ipv6',socket.AF_INET6,'::1',port6)]:
 with socket.socket(family,socket.SOCK_STREAM) as s:
  s.settimeout(3)
  try:
   s.connect((host,int(port)))
   result[label+'_outbound_denied']=False
  except OSError as e:
   result[label+'_outbound_denied']=e.errno in (errno.EPERM,errno.EACCES)
with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
 s.settimeout(3);s.connect(unix);s.sendall(b'local-probe')
 result['unix_socket_success']=s.recv(32)==b'local-ok'
print(json.dumps(result))
'''


def require_result(result):
    expected={'inside_write','outside_write_denied','ipv4_outbound_denied',
              'ipv6_outbound_denied','unix_socket_success'}
    if not isinstance(result,dict) or set(result)!=expected or any(result[k] is not True for k in expected):
        raise ValueError('kernel isolation evidence incomplete')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe',action='store_true')
    parser.add_argument('--output-parent',type=Path,default=Path.home()/'SKO-source-backups')
    args=parser.parse_args()
    if not args.probe:
        print('NOT RUN: no kernel probe, network, credentials, database or SQL activity.')
        return 2
    evidence=None
    sockets=[]
    thread=None
    try:
        if sys.platform!='darwin' or not Path('/usr/bin/sandbox-exec').is_file():
            raise ValueError('macOS sandbox-exec required; no unsandboxed fallback')
        parent=args.output_parent
        if not parent.is_absolute() or parent.is_symlink() or not parent.is_dir():
            raise ValueError('existing private backup parent required')
        st=parent.stat()
        if st.st_uid!=os.getuid() or st.st_mode & 0o022:
            raise ValueError('owned non-writable-by-others parent required')
        os.umask(0o077)
        evidence=Path(tempfile.mkdtemp(prefix='entry-isolation-',dir=str(parent))).resolve()
        evidence.chmod(0o700)
        inside=evidence/'inside';inside.mkdir(mode=0o700)
        outside=evidence/'outside-canary.txt';outside.write_text('unchanged-synthetic-canary')
        unix=inside/'probe.sock'
        # sockaddr_un has a short path limit on macOS; fail rather than relocate outside the protected parent.
        if len(str(unix).encode())>=104:
            raise ValueError('private socket path too long')
        ports=[]
        for family,host in ((socket.AF_INET,'127.0.0.1'),(socket.AF_INET6,'::1')):
            server=socket.socket(family,socket.SOCK_STREAM);sockets.append(server)
            server.bind((host,0));server.listen(4)
            port=server.getsockname()[1];ports.append(port)
            with socket.socket(family,socket.SOCK_STREAM) as control:
                control.settimeout(3);control.connect((host,port))
            connection,_=server.accept();connection.close()
        local=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);sockets.append(local)
        local.bind(str(unix));local.listen(1);local.settimeout(15)
        local_ok=[]
        def respond():
            try:
                connection,_=local.accept()
                with connection:
                    connection.settimeout(3)
                    if connection.recv(32)==b'local-probe':
                        connection.sendall(b'local-ok');local_ok.append(True)
            except OSError:
                pass
        thread=threading.Thread(target=respond,daemon=True);thread.start()
        policy=inside/'profile.sb';policy.write_text(profile(inside,unix))
        env={'PATH':'/usr/bin:/bin','HOME':str(inside),'TMPDIR':str(inside),
             'LANG':'C','LC_ALL':'C','PYTHONDONTWRITEBYTECODE':'1'}
        with (evidence/'private-child-errors.log').open('wb') as errors:
            result=subprocess.run(['/usr/bin/sandbox-exec','-f',str(policy),str(Path(sys.executable).resolve()),
                                   '-c',CHILD,str(inside),str(outside),str(unix),str(ports[0]),str(ports[1])],
                                  env=env,cwd=str(inside),stdout=subprocess.PIPE,stderr=errors,text=True,timeout=20,check=True)
        data=json.loads(result.stdout)
        require_result(data)
        if outside.read_text()!='unchanged-synthetic-canary' or not local_ok:
            raise ValueError('outside canary or unix responder mismatch')
        data.update({'synthetic_kernel_probe_only':True,'postgres_started':False,
                     'archived_sql_executed':False,'production_connections':0,'production_writes':0,
                     'postgres_under_same_profile_verified':False,'complete_egress_or_restore_proof':False})
        (evidence/'private-probe.json').write_text(json.dumps(data,indent=2))
        print('PASS: synthetic IPv4/IPv6 outbound and outside-write denied; fixed UNIX socket and inside-write succeeded.')
        print('PostgreSQL/archived SQL/full isolation and restoration: NOT verified. Production connections/writes: 0.')
        print('Private evidence: '+str(evidence))
        return 2
    except Exception as error:
        print('STOP: kernel probe incomplete ('+type(error).__name__+'). No database or SQL execution; no fallback.')
        if evidence is not None:print('Private evidence: '+str(evidence))
        return 1
    finally:
        for server in sockets:server.close()
        if thread is not None:thread.join(timeout=1)


if __name__=='__main__':raise SystemExit(main())
