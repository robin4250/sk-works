#!/usr/bin/env python3
"""Offline saved pg_restore TOC map only. Never executes a process or SQL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

TABLES={'worker_personnel_profiles','worker_family_members'}
SUPPORT={'workers','companies','company_members','member_feature_permissions','worker_personnel_approvers',
         'worker_personnel_change_requests','worker_personnel_change_approvals'}
FUNCTIONS={'employee_personnel_rows','can_edit_worker_personnel'}
KINDS=('TABLE DATA','TABLE ATTACH','FK CONSTRAINT','DEFAULT ACL','MATERIALIZED VIEW DATA',
       'SEQUENCE SET','SEQUENCE OWNED BY','MATERIALIZED VIEW','PUBLICATION TABLE','FUNCTION',
       'PROCEDURE','CONSTRAINT','TRIGGER','POLICY','INDEX','TABLE','SEQUENCE','SCHEMA','EXTENSION','ACL','DEFAULT')

def classify(text):
    selected=[];seen={};support=[];extensions=[];unresolved=[]
    for line in text.splitlines():
        if not line.strip() or line.startswith(';'):continue
        match=re.fullmatch(r'(\d+);\s+\d+\s+\d+\s+(.+)',line)
        if not match:raise ValueError('unrecognized archive TOC record')
        item=match.group(2);kind=next((k for k in KINDS if item.startswith(k+' ')),None)
        if kind is None:
            unresolved.append(match.group(1));continue
        words=item[len(kind)+1:].split()
        if len(words)<3:raise ValueError('incomplete archive TOC record')
        schema,name=words[0],words[1]
        if kind=='EXTENSION':extensions.append(match.group(1))
        if schema=='public' and name in SUPPORT and kind=='TABLE':support.append(name)
        key=None
        if kind=='TABLE' and schema=='public' and name in TABLES:key='public.'+name
        if kind=='FUNCTION' and schema in ('public','private'):
            routine=name.split('(',1)[0]
            if routine in FUNCTIONS:
                key=schema+'.'+routine
                if (routine=='employee_personnel_rows' and schema!='private') or (routine=='can_edit_worker_personnel' and schema!='public'):
                    raise ValueError('unexpected root function schema; inspect privately')
        if key:
            if key in seen:raise ValueError('ambiguous root overload or duplicate')
            seen[key]=match.group(1);selected.append(line)
    required={'public.'+x for x in TABLES}|{'private.employee_personnel_rows','public.can_edit_worker_personnel'}
    return selected,{'root_count':len(seen),'missing_roots':sorted(required-set(seen)),
        'support_table_names_present':sorted(set(support)),'support_table_names_missing':sorted(SUPPORT-set(support)),
        'extension_entry_count':len(extensions),'unrecognized_entry_count':len(unresolved),
        'schema_only_root_selection':True,'excludes_table_data':True,
        'dependencies_complete':False,'selected_sql_reviewed':False,'time_gap_closed':False,
        'restoration_verified':False,'sql_executed':False,'production_connections':0,'production_writes':0,
        'unverified':['function identity/body hash versus current metadata','FK/default/type/sequence dependencies',
         'policy/ACL/default ACL/trigger function dependencies','support rows and Auth identity invariants',
         'extensions and restored executable code','old archive versus current emails/roles/data']}

def private_file(path):
    if not path.is_absolute() or path.is_symlink() or not path.is_file():raise ValueError('private regular TOC required')
    st=path.stat()
    if st.st_uid!=os.getuid() or st.st_mode&0o077:raise ValueError('private TOC owner permissions required')
    return path

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--toc',type=Path,required=True)
    p.add_argument('--output-parent',type=Path,default=Path.home()/'SKO-source-backups');args=p.parse_args()
    root=None
    try:
        os.umask(0o077);toc=private_file(args.toc);raw=toc.read_bytes()
        if len(raw)>32*1024*1024:raise ValueError('TOC size boundary')
        selected,report=classify(raw.decode())
        parent=args.output_parent
        if not parent.is_absolute() or parent.is_symlink() or not parent.is_dir():raise ValueError('owned parent required')
        st=parent.stat()
        if st.st_uid!=os.getuid() or st.st_mode&0o022:raise ValueError('unsafe parent')
        root=Path(tempfile.mkdtemp(prefix='entry-map-',dir=str(parent)))
        (root/'private-root-candidates.list').write_text('\n'.join(selected)+'\n')
        report['source_toc_sha256']=hashlib.sha256(raw).hexdigest()
        (root/'private-root-map.json').write_text(json.dumps(report,indent=2))
        print('OFFLINE ROOT MAP: '+json.dumps({k:report[k] for k in ('root_count','missing_roots','extension_entry_count','dependencies_complete','sql_executed','production_connections')}))
        print('Candidate roots only; not a runnable restore list. No process, archive SQL, DB or network executed.')
        print('Private evidence: '+str(root));return 2
    except Exception as error:
        print('STOP: offline root map incomplete ('+type(error).__name__+'). No process or SQL executed.')
        if root:print('Private evidence: '+str(root))
        return 1

if __name__=='__main__':raise SystemExit(main())
