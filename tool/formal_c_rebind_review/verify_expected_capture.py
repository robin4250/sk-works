"""Retain real frozen-fixture metadata; never qualifies production deployment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

COMMIT = '74b7107392e3144d37612ec311636f602088f18b'
PINS = {
 'tool/prepare_trade_document_atomic_review_fixture.py':'a49889e8921ff8e43c60c2cd366ccab3a9eeff5d51be551785b70597b00d847a',
 'tool/trade_document_form_server_fixture.mjs':'1392128faa171054b8cbb219061192c47877d72c26e81b431f0bcc0a8f1d8942',
 'tool/verify_trade_documents_deployment_order.mjs':'d82f9a0900e4f2b1e2a952345cd7e3abfb5924d6fbe004eabc55d1f5fd101b20',
 'tool/reset_trade_document_atomic_fixture.mjs':'f732be9b308aa5b8a7d13303226e95f5fce663e6904fd275cc94790afd3dfb7f',
 'docs/review/partner-company-bank-order/native-db.mjs':'c387336da42a9f45a0d751a67adcf89461dcd57a23e41c7bdd31579715e2c8e4',
 'docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only':'7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5',
 'docs/review/trade-document-terms/save-guard.sql.review-only':'e5967ad6b5d54f413ba7db94887423f1f5c98057cafae6c1abed318ce171da5a',
 'docs/review/trade-document-form-input/server-save.sql.review-only':'d57918a806b72e0d52299a3e175c9841258eaa71ce18f2abaab0a7877bd62178',
 'docs/review/trade-document-month-end/server-upgrade.sql.review-only':'bc53ac3daa85452c032d2e2880ca334fe1ce4aee4601cf9cc0be9c6d09818a79',
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 8*1024*1024:
        raise ValueError('Regular bounded capture/source file required')
    return path.read_bytes()

def git(root, *args):
    return subprocess.check_output(['git','-C',str(root),*args], timeout=10).decode().strip()

def verify_sources(root):
    if git(root,'rev-parse','HEAD') != COMMIT:
        raise ValueError('Frozen producer checkout required')
    if git(root,'status','--porcelain','--untracked-files=no'):
        raise ValueError('Tracked frozen source was modified')
    for path, digest in PINS.items():
        if sha(file(root/path)) != digest:
            raise ValueError('Frozen source hash differs: '+path)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-root', type=Path, required=True)
    p.add_argument('--capture', type=Path)
    p.add_argument('--context', type=Path)
    p.add_argument('--output', type=Path)
    p.add_argument('--run-id', type=int)
    p.add_argument('--job-key')
    p.add_argument('--candidate-head')
    p.add_argument('--test-checkout')
    a=p.parse_args()
    verify_sources(a.source_root)
    if a.capture is None:
        print(json.dumps({'frozen_sources_verified':True,'deployable':False}))
        return
    if not all([a.context,a.output,a.run_id,a.job_key,a.candidate_head,a.test_checkout]):
        raise ValueError('Complete actual capture provenance required')
    raw=file(a.capture)
    if a.capture.stat().st_mode & 0o077 or a.context.stat().st_mode & 0o077:
        raise ValueError('Raw capture and context must be private to the owner')
    rows=json.loads(raw)
    if not isinstance(rows,list) or len(rows)!=13:
        raise ValueError('Actual thirteen-record export required')
    ids=set()
    for row in rows:
        if set(row)!={'schema','name','arguments','definition','source_md5','attributes','owner'}:
            raise ValueError('Actual exporter shape differs')
        if row['owner']!='postgres' or row['schema'] not in {'public','private'}:
            raise ValueError('Unexpected owner/schema')
        if not isinstance(row['definition'],str) or not row['definition'].startswith('CREATE OR REPLACE FUNCTION '):
            raise ValueError('Actual complete pg_get_functiondef required')
        attrs=row['attributes']
        if hashlib.md5(attrs['prosrc'].encode()).hexdigest()!=row['source_md5']:
            raise ValueError('Raw source digest differs')
        key=(row['schema'],row['name'],row['arguments'])
        if key in ids:
            raise ValueError('Duplicate exported identity')
        ids.add(key)
    context_raw=file(a.context)
    context=json.loads(context_raw)
    if context['server_version_num']!='170006' or not isinstance(context['default_acls'],list):
        raise ValueError('Actual PG17.6 raw default-ACL context required')
    if a.run_id<=0 or not all(len(s)==40 and all(c in '0123456789abcdef' for c in s) for s in [a.candidate_head,a.test_checkout]):
        raise ValueError('Actual Git/run provenance required')
    result={'contract':'sko.formal_c.native_expected_capture_evidence.v1',
      'source_commit':COMMIT,'source_pins':PINS,'artifact_file_sha256':sha(raw),
      'context_file_sha256':sha(context_raw),'server_version_num':170006,
      'run_id':a.run_id,'job_key':a.job_key,'candidate_head':a.candidate_head,
      'test_checkout':a.test_checkout,'definitions':13,'capture_bytes_unchanged':True,
      'production_defaults_comparison_verified_at_capture_time':False,'independent_review_required':True,
      'registry_updated':False,'production':False,'deployable':False,
      'limitations':['raw fixture defaults require independent comparison with production metadata',
       'full pg_proc/proacl retained without postprocessing',
       'not an admission/drain/realAuth/hosted proof',
       'not a trusted qualifier receipt; reviewer must bind completed job and artifact digest']}
    flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL
    if hasattr(os,'O_NOFOLLOW'):
        flags|=os.O_NOFOLLOW
    with os.fdopen(os.open(a.output,flags,0o600),'w',encoding='utf8') as f:
        json.dump(result,f,sort_keys=True,indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    print(json.dumps(result))

if __name__=='__main__':
    main()
