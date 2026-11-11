#!/usr/bin/env python3
"""Mac local runtime/official-CLI endpoint preflight. No application SQL is sent."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

PROJECT = 'ztktgquxvcxcjxtluspu'
SOURCE = Path(__file__).absolute().parent / 'owner_cli_source'
HELPER_HASHES = {
    'owner_database_capture': '15875c927d90364f8dec1973f5fb1661dc12b9f5242aee5175203f7cb8a8702d',
    'owner_cli_database_capture': 'e4f206b3dab91f98295f2f2a1688a02cc74adb80d00d6262a3f3ce4cc9a300e0',
    'owner_expense_fresh_checkpoint': '85713123cf507ae38f265e0f39433091c0935e0279775d01e94c1e5a8ff48d30',
}

class PreflightFailure(RuntimeError):
    pass

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def owner_helpers():
    # Original fa87 helpers are imported byte-for-byte, never their main().
    for name, expected in HELPER_HASHES.items():
        path = SOURCE / (name + '.py')
        if any(p.is_symlink() for p in (path, *path.parents)) or digest(path) != expected:
            raise PreflightFailure('owner_helper_hash_changed')
        if name in sys.modules and Path(sys.modules[name].__file__).absolute() != path:
            raise PreflightFailure('owner_helper_module_conflict')
    for name in HELPER_HASHES:
        if name not in sys.modules:
            spec = importlib.util.spec_from_file_location(name, SOURCE / (name + '.py'))
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            try:
                spec.loader.exec_module(module)
            except BaseException:
                sys.modules.pop(name, None)
                raise
    return sys.modules['owner_cli_database_capture']

def private_directory(path):
    if not path.is_absolute() or any(p.is_symlink() for p in (path, *path.parents)):
        raise PreflightFailure('private_root_required')
    metadata = path.stat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise PreflightFailure('private_root_required')

def file_info(path, *, owned=False):
    if path.is_symlink() or not path.is_file():
        raise PreflightFailure('runtime_file_invalid')
    metadata=path.stat()
    if owned and metadata.st_uid != os.getuid():
        raise PreflightFailure('runtime_file_invalid')
    if metadata.st_mode & 0o022:
        raise PreflightFailure('runtime_file_writable_by_others')
    return {'path': str(path), 'sha256': digest(path)}

def preflight(state):
    if sys.platform != 'darwin':
        raise PreflightFailure('mac_required')
    cli=owner_helpers()
    home=Path.home()
    parent=home/'SKO-source-backups'
    private_directory(parent)
    root=parent/('expense-default-off-production-'+PROJECT)
    root.mkdir(mode=0o700,exist_ok=True)
    private_directory(root)
    certificate=home/'Downloads'/'prod-ca-2021.crt'
    ca=file_info(certificate,owned=True)
    if not 0 < certificate.stat().st_size <= 1048576:
        raise PreflightFailure('certificate_file_invalid')
    psql=Path(cli.capture.tool('psql')).resolve(strict=True)
    psql_info=file_info(psql)
    version=subprocess.run([str(psql),'--version'],capture_output=True,text=True,check=True,timeout=15)
    pg_match=re.search(r'\(PostgreSQL\) (17\.\d+(?:\.\d+)?)',version.stdout)
    if not pg_match:
        raise PreflightFailure('psql_version_changed')
    executable=shutil.which('supabase')
    if not executable:
        raise PreflightFailure('cli_missing')
    executable=Path(executable).resolve(strict=True)
    cli_info=file_info(executable)
    version=subprocess.run([str(executable),'--version'],capture_output=True,text=True,check=True,timeout=15)
    if version.stdout.strip() != '2.120.0':
        raise PreflightFailure('cli_version_changed')
    # Verify certificate syntax/expiry without any endpoint or database request.
    certificate_check=subprocess.run(['/usr/bin/openssl','x509','-in',str(certificate),'-noout','-checkend','0'],capture_output=True,timeout=15)
    if certificate_check.returncode:
        raise PreflightFailure('certificate_file_invalid')
    state.update(phase='cli_temporary_connection',cli_temporary_role_requested=True)
    with tempfile.TemporaryDirectory(prefix='sko-expense-preflight-',dir=root) as folder:
        work=Path(folder);(work/'supabase').mkdir(mode=0o700)
        (work/'supabase/config.toml').write_text('project_id = "sko-private-capture"\n[db]\nmajor_version = 17\n')
        # Existing official CLI login flow; rendered script is parsed, NEVER run.
        url,password=cli.obtain_connection(work)
        try:
            config=cli.capture.endpoint(url,cli_login=True)
            host=config['PGHOST']
            if not config['PGUSER'].startswith('cli_login_') or config['PGPORT']!='5432':
                raise PreflightFailure('cli_role_or_port_changed')
            state.update(verified=True,phase='verified',host=host,port=5432,
                endpoint_kind='direct' if host=='db.'+PROJECT+'.supabase.co' else 'session_pooler',
                role_kind='cli_login_project' if config['PGUSER'].endswith('.'+PROJECT) else 'cli_login',
                effective_role='postgres',durable_root=str(root),
                psql={**psql_info,'version':pg_match.group(1)},
                cli={**cli_info,'version':'2.120.0'},certificate=ca)
        finally:
            password=None
    if digest(psql)!=psql_info['sha256'] or digest(executable)!=cli_info['sha256'] or digest(certificate)!=ca['sha256']:
        raise PreflightFailure('runtime_file_changed')
    return state

def main():
    os.umask(0o077)
    state={'schema':1,'project':PROJECT,'verified':False,'phase':'local_preflight',
        'cli_temporary_role_requested':False,'application_data_mutations':False,
        'psql_connected':False,'deployment_performed':False,'conversion_performed':False}
    try:
        preflight(state)
    except (Exception,KeyboardInterrupt) as error:
        # Only code-owned failure labels are public. Driver/CLI output is never copied.
        reason=error.args[0] if isinstance(error,PreflightFailure) and error.args else 'preflight_incomplete'
        state.update(verified=False,failure_code=reason if re.fullmatch(r'[a-z_]{1,80}',reason) else 'preflight_incomplete')
    result=json.dumps(state,ensure_ascii=False,sort_keys=True)
    print(result,flush=True)
    if sys.platform=='darwin':
        try:subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=True,timeout=10)
        except (Exception,KeyboardInterrupt):return 1
    return 0 if state['verified'] else 1

if __name__=='__main__':
    raise SystemExit(main())
