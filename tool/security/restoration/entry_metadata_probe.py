#!/usr/bin/env python3
"""Fixed read-only metadata collection; no row export or restoration."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

SNAPSHOT_SHA='432171969b657c082230cc170487e9d7bf9126bdf9a4fa5b19e105c6c3e1e37b'
ROLE_MAP_SHA='f392a6896d20e73b5f2bdb224314867a64c794374e2047a5af819ea563d79f25'
DEFINITIONS_SHA='10fb932c3d13e77abf59d23b42f2e88b3d7551fbdeae98d114acd2df6b576397'

def load_sources(base):
    source=base/'entry_snapshot.py'
    sql=base/'entry_definitions.sql.review-only'
    if source.is_symlink() or sql.is_symlink():raise ValueError('source boundary')
    if hashlib.sha256(source.read_bytes()).hexdigest()!=SNAPSHOT_SHA:raise ValueError('snapshot source mismatch')
    raw=sql.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=DEFINITIONS_SHA:raise ValueError('fixed metadata source mismatch')
    roles_path=base/'entry_role_map.sql.review-only'
    if roles_path.is_symlink():raise ValueError('role source boundary')
    roles=roles_path.read_bytes()
    if hashlib.sha256(roles).hexdigest()!=ROLE_MAP_SHA:raise ValueError('fixed role map source mismatch')
    spec=importlib.util.spec_from_file_location('_entry_reviewed_snapshot',source)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    collector,invariants,_=module.reviewed_queries(base)
    query=("SELECT pg_catalog.jsonb_build_object('read_only', "
           "pg_catalog.current_setting('transaction_read_only')='on', 'payload', ("+
           "SELECT pg_catalog.jsonb_build_object('read_only', pg_catalog.current_setting('transaction_read_only')='on', 'definitions', ("+
           raw.decode().strip().rstrip(';')+"), 'role_map', ("+roles.decode()+")))) AS entry_payload;")
    return module,collector,invariants,query

def collect(module,collector,invariants,query,parent):
    root=collector.new_capsule_directory(parent)
    try:
        token=module.token_from_store(os.environ)
        opener=module.make_opener()
        before=module.read_query(opener,token,invariants)
        (root/'private-before.json').write_text(json.dumps(before))
        metadata=module.read_query(opener,token,query)
        if metadata['payload'].get('read_only') is not True:raise ValueError('metadata read-only proof missing')
        (root/'private-definitions.json').write_text(json.dumps(metadata))
        after=module.read_query(opener,token,invariants)
        (root/'private-after.json').write_text(json.dumps(after))
        if before!=after:raise ValueError('identity membership drift')
        (root/'private-manifest.json').write_text(json.dumps({
            'fixed_metadata_sql_sha256':DEFINITIONS_SHA,'fixed_role_map_sql_sha256':ROLE_MAP_SHA,
            'definitions_and_role_map_same_statement':True,'read_only_proven':True,
            'before_after_invariants_equal':True,'production_writes':0,
            'business_auth_row_export':False,'schema_archive':False,
            'transitive_dependency_closure':False,'data_time_gap_closed':False,
            'restoration_verified':False,
            'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.is_file()}
        },indent=2))
        print('COLLECTED PRIVATELY: fixed personnel/support metadata; read-only proven; minimal invariants unchanged.')
        print('Business/Auth rows, archive equality, dependency closure and restoration: NOT verified. Production writes: 0.')
        print('Private evidence: '+str(root))
        return 2
    except Exception as error:
        print('STOP: fixed metadata collection incomplete ('+type(error).__name__+'). No production write.')
        print('Private evidence: '+str(root))
        return 1

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect',action='store_true')
    parser.add_argument('--output-parent',type=Path,default=Path.home()/'SKO-source-backups')
    args=parser.parse_args()
    if not args.collect:
        print('NOT RUN: no credential access, API request, SQL execution or restoration.')
        return 2
    os.umask(0o077)
    try:
        module,collector,invariants,query=load_sources(Path(__file__).parent)
        return collect(module,collector,invariants,query,args.output_parent)
    except Exception as error:
        print('STOP: metadata preparation incomplete ('+type(error).__name__+'). No production write.')
        return 1

if __name__=='__main__':raise SystemExit(main())
