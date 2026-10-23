"""Preferred owner transport: pinned official CLI credentials + native PG17 psql.

No login, credential discovery, connection or application SQL at import/CLI time.
Production binding remains unset. A synthetic native TLS fixture uses this class.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from owner_cli_preflight import owner_helpers, digest, PROJECT, private_directory
from production_transport_binding import APPROVED_DURABLE_ROOT, APPROVED_MANIFEST_SHA256
from review_runner import FILES, MAX_BYTES, Refused, read_private, install_review_once, recover_review_readonly

RUNTIME=Path(__file__).absolute().parent
CODE_FILES=('cli_psql_transport.py','owner_cli_preflight.py','review_runner.py','offline_generator.mjs',
            'offline_docker_generator.py','offline_docker_generator.sh')

def _sha(value):return hashlib.sha256(value).hexdigest()

class CliPsqlTransport:
    def __init__(self,config,password,psql,certificate,artifacts,expected_host):
        # Config comes from the hash-pinned original parser; endpoint is validated
        # a second time and locked to the owner-approved concrete host.
        cli=owner_helpers()
        from urllib.parse import quote
        url='postgresql://'+quote(config.get('PGUSER',''),safe='')+'@'+config.get('PGHOST','')+':'+config.get('PGPORT','')+'/'+config.get('PGDATABASE','')
        exact=cli.capture.endpoint(url,cli_login=True)
        if exact!=config or exact['PGHOST']!=expected_host or not exact['PGUSER'].startswith('cli_login_') or not password or '\0' in password:
            raise Refused('cli_connection_binding_refused')
        self.config,self.password=config.copy(),password
        self.psql,self.certificate=Path(psql),Path(certificate)
        self.psql_hash,self.ca_hash=digest(self.psql),digest(self.certificate)
        self.artifacts=artifacts.copy();self.attempted=False

    def _request(self,mode,sql):
        name=FILES[1] if mode=='install' else FILES[2]
        if not isinstance(sql,bytes) or not 0<len(sql)<=MAX_BYTES or _sha(sql)!=self.artifacts.get(name):
            raise Refused('approved_sql_differs')
        if digest(self.psql)!=self.psql_hash or digest(self.certificate)!=self.ca_hash:
            raise Refused('psql_or_ca_changed')
        # No inherited PG service/options, shell, .psqlrc or password file.
        env={**self.config,'PGPASSWORD':self.password,'PGSSLMODE':'verify-full',
            'PGSSLROOTCERT':str(self.certificate),'PGCONNECT_TIMEOUT':'10',
            'PGPASSFILE':'/dev/null','PGSERVICEFILE':'/dev/null',
            'PGOPTIONS':'-c search_path=public -c statement_timeout=30000 -c lock_timeout=3000 -c idle_in_transaction_session_timeout=35000'+
                (' -c default_transaction_read_only=on' if mode=='read-only' else ''),
            'LC_ALL':'C','LANG':'C'}
        args=[str(self.psql),'-X','-w','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate']
        try:
            result=subprocess.run(args,input=sql,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                env=env,timeout=45,close_fds=True)
        except (Exception,KeyboardInterrupt):
            raise ConnectionError('psql_result_unknown') from None
        finally:env.pop('PGPASSWORD',None)
        if result.returncode or len(result.stdout)>MAX_BYTES:
            raise ConnectionError('psql_result_unknown')
        if mode=='install':
            if result.stdout.strip():raise ConnectionError('psql_commit_ack_unknown')
            return b''
        try:
            value=json.loads(result.stdout)
            if not isinstance(value,dict) or value.get('read_only')!='on':raise ValueError()
        except Exception:
            raise ConnectionError('psql_readonly_result_invalid') from None
        return result.stdout.strip()

    def execute_install_once(self,sql):
        if self.attempted:raise Refused('transport_install_already_attempted')
        self.attempted=True
        self._request('install',sql)

    def capture_readonly(self,sql):
        return self._request('read-only',sql)

def _approved_binding():
    if APPROVED_DURABLE_ROOT is None or APPROVED_MANIFEST_SHA256 is None:
        raise Refused('production_binding_not_approved')
    if sys.platform!='darwin':raise Refused('mac_required')
    root=APPROVED_DURABLE_ROOT;private_directory(root)
    raw=read_private(root/'production-approval.json')
    if _sha(raw)!=APPROVED_MANIFEST_SHA256:raise Refused('production_approval_hash_differs')
    value=json.loads(raw)
    if set(value)!={'schema','transport','project','host','port','role_kind','effective_role','root','psql','cli','certificate','node','artifacts','code'} or value['schema']!=2 or value['transport']!='owner_cli_psql' or value['project']!=PROJECT or value['port']!=5432 or value['effective_role']!='postgres' or value['root']!=str(root) or value['role_kind'] not in ('cli_login','cli_login_project'):
        raise Refused('production_binding_refused')
    if set(value['artifacts'])!={*FILES,'prepare-status.json'} or set(value['code'])!=set(CODE_FILES):raise Refused('approval_hash_set_refused')
    for name in (*FILES,'prepare-status.json'):
        if _sha(read_private(root/'prepared'/name))!=value['artifacts'][name]:raise Refused('approved_artifact_differs')
    for name in CODE_FILES:
        if (RUNTIME/name).is_symlink() or digest(RUNTIME/name)!=value['code'][name]:raise Refused('approved_code_differs')
    owner_helpers() # All three original fa87 modules must match before auth.
    for name in ('psql','cli','certificate','node'):
        item=value[name];path=Path(item['path'])
        if not path.is_absolute() or path.is_symlink() or not path.is_file() or digest(path)!=item['sha256']:raise Refused('approved_runtime_differs')
    if Path(value['certificate']['path'])!=Path.home()/'Downloads'/'prod-ca-2021.crt':raise Refused('approved_ca_path_differs')
    return value

def _operator_transport(binding):
    cli=owner_helpers()
    if cli.capture.tool('psql')!=binding['psql']['path']:
        # Homebrew symlinks resolve to the same approved concrete binary.
        if Path(cli.capture.tool('psql')).resolve()!=Path(binding['psql']['path']):raise Refused('psql_path_changed')
    check=subprocess.run([binding['cli']['path'],'--version'],capture_output=True,text=True,check=True,timeout=15)
    if check.stdout.strip()!='2.120.0':raise Refused('cli_version_changed')
    # The original CLI helper invokes 'supabase' by PATH; fix PATH to its approved
    # directory only. No account/token/password files are opened by this code.
    old_path=os.environ.get('PATH')
    try:
        os.environ['PATH']=str(Path(binding['cli']['path']).parent)+':/usr/bin:/bin'
        with tempfile.TemporaryDirectory(prefix='sko-expense-cli-',dir=APPROVED_DURABLE_ROOT) as folder:
            work=Path(folder);(work/'supabase').mkdir(mode=0o700)
            (work/'supabase/config.toml').write_text('project_id = "sko-private-capture"\n[db]\nmajor_version = 17\n')
            url,password=cli.obtain_connection(work)
    finally:
        if old_path is None:os.environ.pop('PATH',None)
        else:os.environ['PATH']=old_path
    config=cli.capture.endpoint(url,cli_login=True)
    role_kind='cli_login_project' if config['PGUSER'].endswith('.'+PROJECT) else 'cli_login'
    if role_kind!=binding['role_kind']:raise Refused('cli_role_kind_changed')
    return CliPsqlTransport(config,password,binding['psql']['path'],binding['certificate']['path'],binding['artifacts'],binding['host'])

def install_cli_approved_once():
    binding=_approved_binding()
    transport=_operator_transport(binding)
    return install_review_once(APPROVED_DURABLE_ROOT/'prepared',APPROVED_DURABLE_ROOT,transport,binding['node']['path'])

def recover_cli_approved_readonly():
    binding=_approved_binding()
    transport=_operator_transport(binding)
    return recover_review_readonly(APPROVED_DURABLE_ROOT,transport,binding['node']['path'])

if __name__=='__main__':
    print('production_operator_binding_required')
    raise SystemExit(2)
