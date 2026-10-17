#!/usr/bin/env python3
"""P36 synthetic read-boundary/native probe. No archive or production input."""
import argparse
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

NATIVE_SHA="e080889f7d849cf4d632181f2d4d9a79e6dcacd36f390855acd572ab9d4ae950"
SYSTEM_ROOTS=("/System","/usr/lib","/usr/share","/usr/bin","/usr/sbin","/bin","/sbin","/Library/Apple")
SYSTEM_FILES=("/dev/null","/dev/urandom","/dev/random","/dev/zero","/private/etc/localtime","/private/etc/locale.alias")

def quote(path):
    text=str(path)
    if any(ord(c)<32 for c in text):raise ValueError("Control character in profile path")
    return '"'+text.replace('\\','\\\\').replace('"','\\"')+'"'

def runtime_root(path):
    resolved=Path(path).resolve(strict=True)
    forbidden={Path('/'),Path('/usr'),Path('/usr/local'),Path('/opt'),Path('/opt/homebrew'),
               Path('/opt/homebrew/Cellar'),Path('/Library'),Path('/Users'),Path.home()}
    if not resolved.is_dir() or resolved in forbidden or resolved in Path.home().parents:
        raise ValueError("Overbroad runtime root")
    return resolved

def library_reference(text, binary):
    if text.startswith('@loader_path/'):return binary.parent/text[len('@loader_path/'):]
    if text.startswith('@executable_path/'):return binary.parent/text[len('@executable_path/'):]
    if text.startswith('@') or not text.startswith('/'):raise ValueError("Unresolved runtime library: "+text[:1000])
    return Path(text)

def parse_otool(text,binary):
    # Apple cctools emits a separate exact filename header for each fat slice.
    header=re.compile(re.escape(str(binary))+r'(?: \(architecture (arm64|x86_64)\))?:')
    seen=set();entries=[]
    for line in text.splitlines():
        h=header.fullmatch(line)
        if h:
            kind=h.group(1) or 'native'
            if kind in seen:raise ValueError("Duplicate runtime architecture header")
            seen.add(kind);continue
        m=re.fullmatch(r'\s+(.+?) \(compatibility version .+\)',line)
        if not seen or not m:
            raise ValueError("Unexpected runtime library metadata for "+binary.name+": "+repr(line[:1000]))
        entries.append(m.group(1))
    if not seen:raise ValueError("Runtime library header required")
    return entries

def libraries(binaries):
    pending=[Path(p).resolve(strict=True) for p in binaries];seen=set();allowed=set()
    env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'}
    while pending:
        binary=pending.pop()
        if binary in seen:continue
        seen.add(binary)
        if len(seen)>128:raise ValueError("Runtime dependency limit")
        r=subprocess.run(['/usr/bin/otool','-L',str(binary)],capture_output=True,text=True,
                         check=True,timeout=10,env=env)
        for name in parse_otool(r.stdout,binary):
            ref=library_reference(name,binary)
            if any(ref==Path(p) or Path(p) in ref.parents for p in SYSTEM_ROOTS):
                continue # macOS shared-cache files need not be present on disk.
            real=ref.resolve(strict=True)
            if not real.is_file():raise ValueError("Runtime library not regular")
            allowed.add(real);pending.append(real)
    return tuple(sorted(allowed))

def timezone_runtime(pg_bin, runner=subprocess.run):
    pg_bin=Path(pg_bin).resolve(strict=True);pg_root=runtime_root(pg_bin.parent)
    if pg_root.parent.name!='postgresql@17' or pg_root.parent.parent.name!='Cellar':
        raise ValueError("PostgreSQL17 Cellar boundary required")
    config=pg_bin/'pg_config';real=config.resolve(strict=True)
    if not real.is_file() or pg_root not in real.parents:
        raise ValueError("pg_config outside same runtime")
    env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'}
    def setting(flag):
        r=runner([str(config),flag],capture_output=True,text=True,check=True,timeout=10,env=env)
        value=r.stdout.rstrip('\n')
        if '\n' in value or '\r' in value or not value:raise ValueError("Unexpected pg_config output")
        return value
    version=setting('--version')
    match=re.fullmatch(r'PostgreSQL (17\.\d+(?:\.\d+)?)(?: \([^)]*\))?',version)
    if not match or match.group(1)!=pg_root.name.split('_',1)[0]:
        raise ValueError("Different pg_config runtime version")
    if Path(setting('--bindir')).resolve(strict=True)!=pg_bin:
        raise ValueError("Different pg_config bindir")
    shared=pg_root.parents[2]/'share/postgresql@17'
    if Path(setting('--sharedir'))!=shared:
        raise ValueError("Unexpected compiled sharedir")
    canonical=(pg_root/'share/postgresql/timezone').resolve(strict=True)
    alias=shared/'timezone'
    if not canonical.is_dir() or pg_root not in canonical.parents or alias.resolve(strict=True)!=canonical:
        raise ValueError("Unknown or drifted timezone runtime alias: "+json.dumps({
            "canonical":str(canonical),"canonical_is_dir":canonical.is_dir(),
            "canonical_within_package":pg_root in canonical.parents,
            "alias":str(alias),"alias_resolved":str(alias.resolve(strict=True)),
            "alias_is_symlink":alias.is_symlink(),"alias_is_dir":alias.is_dir(),
            "same_target":alias.resolve(strict=True)==canonical}))
    # Runtime owner must match this package's pg_config; never allow data/extension trees.
    owner=real.stat().st_uid
    for directory in (canonical,shared,alias.resolve(strict=True)):
        st=directory.stat()
        if not directory.is_dir() or st.st_uid!=owner or st.st_mode&0o022:
            raise ValueError("Unsafe runtime data owner or mode")
    hashes={name:hashlib.sha256((pg_bin/name).read_bytes()).hexdigest() for name in
            ('postgres','psql','initdb','pg_ctl','pg_config')}
    return alias,{'timezone_canonical':str(canonical),'timezone_alias':str(alias),
                  'compiled_sharedir':str(shared),'version':version,'owner_uid':owner,
                  'binary_sha256':hashes}

def profile(inside, unix, roots, files):
    inside=Path(inside);unix=Path(unix)
    if not inside.is_absolute() or not unix.is_absolute() or unix.parent!=inside:
        raise ValueError("Fixed private socket required")
    lines=['(version 1)','(deny default)','(import "system.sb")',
           '(allow file-read-metadata)','(allow process*)','(deny network*)']
    for root in [inside,*map(Path,SYSTEM_ROOTS),*roots]:
        lines.append('(allow file-read-data (subpath '+quote(root)+'))')
    for file in [*map(Path,SYSTEM_FILES),*files]:
        lines.append('(allow file-read-data (literal '+quote(file)+'))')
    lines+=['(allow file-write* (subpath '+quote(inside)+'))',
            '(allow network-outbound (remote unix-socket (literal '+quote(unix)+')))',
            '(allow network-inbound (local unix-socket (literal '+quote(unix)+')))']
    return '\n'.join(lines)+'\n'

CHILD=r"""
import errno,json,pathlib,sys
inside,outside=sys.argv[1:]
result={}
result['inside_read']=pathlib.Path(inside,'inside.txt').read_text()=='synthetic-inside'
for name,path in [('outside_read_denied',pathlib.Path(outside)),('symlink_read_denied',pathlib.Path(inside,'outside-link'))]:
 try:
  path.read_bytes()
  result[name]=False
 except OSError as e:
  result[name]=e.errno in (errno.EACCES,errno.EPERM)
print(json.dumps(result))
"""

def read_probe(guard,native,parent):
    evidence=Path(tempfile.mkdtemp(prefix='p36-read-',dir=parent));evidence.chmod(0o700)
    inside=evidence/'inside';inside.mkdir(mode=0o700)
    print('Read-boundary evidence: '+str(evidence))
    outside=evidence/'private-canary.txt';outside.write_text('synthetic-outside-no-private-data')
    (inside/'inside.txt').write_text('synthetic-inside')
    (inside/'outside-link').symlink_to(outside)
    policy=inside/'profile.sb'
    policy.write_text(guard.profile(inside,inside/'.s.PGSQL.5432'))
    with (evidence/'private-read-errors.log').open('wb') as errors:
        r=subprocess.run(['/usr/bin/sandbox-exec','-f',str(policy),str(Path(sys.executable).resolve()),
                          '-c',CHILD,str(inside),str(outside)],stdout=subprocess.PIPE,stderr=errors,
                         text=True,env=native.clean_environment(inside),cwd=inside,timeout=30,check=True)
    result=json.loads(r.stdout)
    expected={'inside_read':True,'outside_read_denied':True,'symlink_read_denied':True}
    if result!=expected or any(x is not True for x in result.values()):
        raise ValueError("Host read boundary not established")
    (evidence/'private-read-report.json').write_text(json.dumps(result,indent=2))
    return evidence

def load_native(path):
    if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest()!=NATIVE_SHA:
        raise ValueError("Reviewed native source mismatch")
    spec=importlib.util.spec_from_file_location('_p36_native',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--probe',action='store_true')
    p.add_argument('--sources',required=True,type=Path)
    p.add_argument('--pg-bin',required=True,type=Path)
    p.add_argument('--output-parent',required=True,type=Path)
    args=p.parse_args()
    if not args.probe:
        print('NOT RUN: no native startup, credential, database or archive access.');return 2
    evidence=None;stage='platform'
    try:
        if sys.platform!='darwin':raise ValueError("macOS only; no fallback")
        parent=args.output_parent
        if not parent.is_absolute() or parent.is_symlink() or not parent.is_dir():raise ValueError("Private parent required")
        st=parent.stat()
        if st.st_uid!=os.getuid() or st.st_mode&0o022:raise ValueError("Unsafe parent")
        os.umask(0o077)
        evidence=Path(tempfile.mkdtemp(prefix='p36-context-',dir=parent));evidence.chmod(0o700)
        stage='runtime-roots'
        pg_bin=args.pg_bin.resolve(strict=True)
        if not all((pg_bin/n).is_file() for n in ('postgres','psql','initdb','pg_ctl')):raise ValueError("Explicit native tools required")
        pg_root=runtime_root(pg_bin.parent)
        if pg_root.parent.name!='postgresql@17' or pg_root.parent.parent.name!='Cellar':raise ValueError('Explicit Homebrew PostgreSQL17 runtime required')
        stage='same-package-timezone-alias'
        timezone,package=timezone_runtime(pg_bin)
        roots=(pg_root,runtime_root(sys.base_prefix),timezone)
        stage='runtime-library-closure'
        files=libraries([pg_bin/n for n in ('postgres','psql','initdb','pg_ctl')]+[Path(sys.executable)])
        stage='reviewed-helper-loading'
        native=load_native(args.sources/'entry_native_probe.py')
        original_load=native.load_guard;original_verify=native.verify_host
        reads=[]
        def load_guard(path):
            guard=original_load(path)
            guard.profile=lambda inside,unix:profile(inside,unix,roots,files)
            return guard
        def verify_host(guard,parent):
            evidence=read_probe(guard,native,parent);reads.append(evidence)
            return original_verify(guard,parent)
        native.load_guard=load_guard;native.verify_host=verify_host
        old=sys.argv
        try:
            sys.argv=['p36-native','--probe','--pg-bin',str(pg_bin),'--output-parent',str(parent)]
            stage='read-kernel-native-probes'
            code=native.main()
        finally:sys.argv=old
        if code!=2 or len(reads)!=1:raise ValueError("Native/read proof incomplete")
        if timezone_runtime(pg_bin)[1]!=package:raise ValueError('Runtime package or timezone alias drift during probe')
        evidence=reads[0]
        (evidence/'private-runtime-inventory.json').write_text(json.dumps({
            'postgres_runtime':package,'roots':[str(x) for x in roots],'libraries':[str(x) for x in files],
            'read_canary_verified':True,'native_kernel_fixture_success':True,
            'existing_archive_read':False,'archived_sql_executed':False,
            'complete_read_isolation_or_egress_proof':False,
            'production_connections':0,'production_writes':0},indent=2))
        print('PASS P36: outside and symlink canary reads denied; inside read, fixed UNIX, IPv4/v6/outside-write checks and native synthetic PostgreSQL succeeded.')
        print('Actual archives, arbitrary runtime isolation and full restoration: NOT verified. Production connections/writes: 0.')
        print('Private evidence: '+str(evidence));return 2
    except Exception as error:
        if evidence is not None:
            (evidence/'private-p36-error.json').write_text(json.dumps({'stage':stage,'kind':type(error).__name__,'message':str(error)}))
        print('STOP: P36 read/native boundary incomplete ('+stage+'/'+type(error).__name__+'); no archive or production execution.')
        if evidence is not None:print('Private evidence: '+str(evidence))
        return 1

if __name__=='__main__':raise SystemExit(main())
