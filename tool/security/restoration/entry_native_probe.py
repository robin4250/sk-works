#!/usr/bin/env python3
"""Synthetic PostgreSQL 17 sandbox probe. No existing archive or DB is read."""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tempfile

GUARD_SHA='6f99985a38ec66f53528d6eb9f37643a442712d6e3509df539318d30357628f9'
SQL="""
CREATE ROLE sko_probe_reader NOLOGIN;
CREATE TABLE public.sko_probe_rows(id integer PRIMARY KEY, marker text NOT NULL);
INSERT INTO public.sko_probe_rows VALUES(1,'synthetic-only');
GRANT SELECT ON public.sko_probe_rows TO sko_probe_reader;
SET ROLE sko_probe_reader;
SELECT json_build_object('reader_access',count(*)=1 AND min(marker)='synthetic-only') FROM public.sko_probe_rows;
RESET ROLE;
BEGIN;
UPDATE public.sko_probe_rows SET marker='discarded';
REVOKE SELECT ON public.sko_probe_rows FROM sko_probe_reader;
ROLLBACK;
SET ROLE sko_probe_reader;
SELECT json_build_object('rollback_preserved',count(*)=1 AND min(marker)='synthetic-only') FROM public.sko_probe_rows;
RESET ROLE;
DROP TABLE public.sko_probe_rows;
DROP ROLE sko_probe_reader;
SELECT json_build_object('synthetic_cleanup',to_regclass('public.sko_probe_rows') IS NULL
 AND NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='sko_probe_reader'));
"""


def load_guard(path):
    if hashlib.sha256(path.read_bytes()).hexdigest()!=GUARD_SHA:
        raise ValueError('reviewed isolation source mismatch')
    spec=importlib.util.spec_from_file_location('_native_guard',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def clean_environment(inside, source=os.environ):
    # Intentionally do not inherit any credential, service, preload or user rc configuration.
    return {'PATH':'/usr/bin:/bin','HOME':str(inside),'TMPDIR':str(inside),
            'LANG':'C','LC_ALL':'C','PYTHONDONTWRITEBYTECODE':'1'}


def parse_flags(text):
    rows=[json.loads(line) for line in text.splitlines() if line.startswith('{')]
    expected=[{'reader_access':True},{'rollback_preserved':True},{'synthetic_cleanup':True}]
    if rows!=expected or any(any(value is not True for value in row.values()) for row in rows):
        raise ValueError('native synthetic proof incomplete')


def verify_host(guard,parent):
    previous=sys.argv
    output=io.StringIO()
    try:
        sys.argv=['entry-isolation','--probe','--output-parent',str(parent)]
        with contextlib.redirect_stdout(output):code=guard.main()
    finally:sys.argv=previous
    if code!=2:raise ValueError('same-host kernel probe failed')
    lines=output.getvalue().splitlines()
    matches=[line[len('Private evidence: '):] for line in lines if line.startswith('Private evidence: ')]
    if len(matches)!=1:raise ValueError('same-host kernel evidence missing')
    evidence=Path(matches[0])
    if evidence.parent!=parent.resolve():raise ValueError('same-host evidence boundary mismatch')
    report=json.loads((evidence/'private-probe.json').read_text())
    keys=('inside_write','outside_write_denied','ipv4_outbound_denied','ipv6_outbound_denied','unix_socket_success')
    if any(report.get(k) is not True for k in keys):raise ValueError('same-host kernel proof incomplete')
    return evidence


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe',action='store_true')
    parser.add_argument('--pg-bin',required=True,type=Path)
    parser.add_argument('--output-parent',type=Path,default=Path.home()/'SKO-source-backups')
    args=parser.parse_args()
    if not args.probe:
        print('NOT RUN: no PostgreSQL startup, credentials, API or SQL execution.')
        return 2
    evidence=None;started=False;attempted=False;shutdown=False;errors=None
    run=None
    try:
        if sys.platform!='darwin' or not Path('/usr/bin/sandbox-exec').is_file():
            raise ValueError('macOS sandbox-exec required; no fallback')
        guard=load_guard(Path(__file__).with_name('entry_isolation.py'))
        parent=args.output_parent
        if not parent.is_absolute() or parent.is_symlink() or not parent.is_dir():
            raise ValueError('existing owned backup parent required')
        st=parent.stat()
        if st.st_uid!=os.getuid() or st.st_mode & 0o022:
            raise ValueError('unsafe backup parent')
        binaries={n:args.pg_bin/n for n in ('initdb','pg_ctl','postgres','psql')}
        if not all(p.is_absolute() and p.is_file() for p in binaries.values()):
            raise ValueError('explicit native PostgreSQL tools required')
        kernel_evidence=verify_host(guard,parent)
        os.umask(0o077)
        evidence=Path(tempfile.mkdtemp(prefix='entry-native-',dir=str(parent))).resolve();evidence.chmod(0o700)
        inside=evidence/'inside';inside.mkdir(mode=0o700)
        data=inside/'pgdata';sock=inside/'s';sock.mkdir(mode=0o700)
        endpoint=sock/'.s.PGSQL.5432'
        if len(str(endpoint).encode())>=104:raise ValueError('private socket path too long')
        policy=inside/'profile.sb';policy.write_text(guard.profile(inside,endpoint))
        env=clean_environment(inside)
        errors=(evidence/'private-native-errors.log').open('wb')
        def run(command,timeout=30,check=True):
            argv=['/usr/bin/sandbox-exec','-f',str(policy)]+[str(x) for x in command]
            with subprocess.Popen(argv,env=env,cwd=str(inside),stdout=subprocess.PIPE,stderr=errors,
                                  text=True,start_new_session=True) as process:
                try:output,_=process.communicate(timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGTERM)
                    try:process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid,signal.SIGKILL);process.communicate()
                    raise
                result=subprocess.CompletedProcess(argv,process.returncode,output)
                if check and result.returncode:raise subprocess.CalledProcessError(result.returncode,argv)
                return result
        for binary in binaries.values():
            if not re.search(r'\b17\.',run([binary,'--version']).stdout):
                raise ValueError('PostgreSQL 17 required')
        run([binaries['initdb'],'-D',data,'-U','sko_probe_operator','--auth-local=trust',
             '--auth-host=reject','--no-locale','-E','UTF8'],timeout=90)
        options=shlex.join(['-h','','-k',str(sock),'-p','5432','-c','shared_preload_libraries=',
                            '-c','max_worker_processes=0','-c','max_parallel_workers=0','-c','logging_collector=off'])
        attempted=True
        run([binaries['pg_ctl'],'-D',data,'-l',inside/'server.log','-o',options,'-w','-t','20','start'])
        started=True
        base=[binaries['psql'],'-X','-w','-qAt','-v','ON_ERROR_STOP=1','-h',sock,'-p','5432',
              '-U','sko_probe_operator','-d','postgres']
        connection=run(base+['-c',"SELECT json_build_object('data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'local',inet_server_addr() IS NULL);"])
        actual=json.loads(connection.stdout.strip())
        if actual!={'data':str(data),'socket':str(sock),'listen':'','local':True} or actual['local'] is not True:
            raise ValueError('new private socket cluster identity mismatch')
        run(base+['-c','CREATE DATABASE sko_probe;'])
        result=run(base[:-1]+['sko_probe','-c',SQL])
        parse_flags(result.stdout)
        (inside/'synthetic-proof.json').write_text(result.stdout)
        run(base+['-c','DROP DATABASE sko_probe;'])
        run([binaries['pg_ctl'],'-D',data,'-m','fast','-w','-t','20','stop'])
        shutdown=True;started=False
        status=run([binaries['pg_ctl'],'-D',data,'status'],check=False)
        if status.returncode!=3:raise ValueError('shutdown not established')
        report={'postgres_17_same_profile_started':True,'socket_only':True,'synthetic_role_table_rollback':True,
                'clean_shutdown':True,'production_connections':0,'production_writes':0,
                'existing_archive_read':False,'archived_sql_executed':False,'full_restoration_verified':False,
                'same_host_kernel_probe_verified':True,'kernel_evidence':str(kernel_evidence),
                'complete_egress_proof':False}
        (evidence/'private-native-report.json').write_text(json.dumps(report,indent=2))
        print('PASS: native PostgreSQL 17 under fixed sandbox; new socket-only cluster; synthetic role/table access and rollback; clean shutdown.')
        print('Existing archives/data untouched. Archived SQL/full restoration: NOT verified. Production connections/writes: 0.')
        print('Private evidence: '+str(evidence))
        return 2
    except Exception as error:
        print('STOP: native synthetic probe incomplete ('+type(error).__name__+'). No existing archive or production access.')
        if evidence is not None:print('Private evidence: '+str(evidence))
        return 1
    finally:
        if attempted and not shutdown and run is not None:
            try:
                run([binaries['pg_ctl'],'-D',data,'-m','fast','-w','-t','20','stop'],check=False)
                status=run([binaries['pg_ctl'],'-D',data,'status'],check=False)
                if status.returncode!=3:print('STOP: private test cluster shutdown needs local inspection.')
            except Exception:print('STOP: private test cluster shutdown not verified; inspect private evidence locally.')
        if errors is not None:errors.close()


if __name__=='__main__':raise SystemExit(main())
