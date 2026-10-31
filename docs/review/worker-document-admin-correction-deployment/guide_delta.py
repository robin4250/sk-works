#!/usr/bin/env python3
"""Offline proof only. No DB, migration, application, or automatic rebaseline."""
import argparse,hashlib,json,pathlib,re
SEAL_SHA='6874c873dd404610c99f48ab014139927b9ae2d75df383c18bde10118a8f2a97'
EMPTY_SHA=hashlib.sha256(b'').hexdigest()
NAME='current_user_required_document_attention_for_company'
DOC_RUNTIME_SHA='8e7dcb4b2fcc3fe77ada3c5d39333d1cb0802858690fd59584d216436868b04a'
def export_sha(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
def check(before,after,receipt,seal,approved_before_sha,approved_before_export_sha,reviewed_binding):
 if not re.fullmatch('[a-f0-9]{64}',approved_before_sha) or before.get('snapshot_sha256')!=approved_before_sha:raise ValueError('approved before capture mismatch')
 if not re.fullmatch('[a-f0-9]{64}',after.get('snapshot_sha256','')):raise ValueError('server after capture required')
 b=before['snapshot'];a=after['snapshot']
 if not re.fullmatch('[a-f0-9]{64}',approved_before_export_sha) or export_sha(b)!=approved_before_export_sha:raise ValueError('before snapshot not bound to approved proposal export')
 if reviewed_binding.get('contract')!='independently_reviewed_guide_after_capture_v1' or reviewed_binding.get('before_export_sha256')!=approved_before_export_sha or reviewed_binding.get('after_export_sha256')!=export_sha(a) or reviewed_binding.get('endpoints_export_sha256')!=export_sha(receipt) or reviewed_binding.get('after_server_snapshot_sha256')!=after['snapshot_sha256'] or reviewed_binding.get('guide_seal_sha256')!=SEAL_SHA or not re.fullmatch('[a-f0-9]{64}',reviewed_binding.get('independent_review_receipt_sha256','')):raise ValueError('after capture/endpoints require externally reviewed binding')
 if {k:v for k,v in b.items() if k!='functions'}!={k:v for k,v in a.items() if k!='functions'}:raise ValueError('unknown nonfunction catalog difference')
 if b.get('role')!='postgres' or b.get('server_version_num')!=170006 or b.get('version')!=2:raise ValueError('reviewed server and role required')
 def indexed(rows):
  result={r['oid']:r for r in rows}
  if len(result)!=len(rows):raise ValueError('duplicate function OID')
  return result
 old=indexed(b['functions']);new=indexed(a['functions'])
 if any(new.get(oid)!=value for oid,value in old.items()):raise ValueError('existing function changed or disappeared')
 if any(r['proname']==NAME and r['nspname'] in('private','public') for r in old.values()):raise ValueError('guide endpoint already existed before')
 added=[v for k,v in new.items() if k not in old]
 if len(added)!=2 or {(r['nspname'],r['proname'],r['args']) for r in added}!={('private',NAME,'2950'),('public',NAME,'2950')}:raise ValueError('only exact two guide functions may be added')
 if len(receipt)!=2 or {r['oid'] for r in receipt}!={r['oid'] for r in added}:raise ValueError('exact postcommit endpoint receipt required')
 expected={x['nspname']:x['catalog'] for x in seal}
 acl=[{'role':r,'grantor':'postgres','privilege':'EXECUTE','grant_option':False} for r in ['authenticated','postgres']]
 for r in receipt:
  fn=new[r['oid']]
  if any(r[k]!=fn[k] for k in ['nspname','proname','args','attributes_sha256','comment_sha256']):raise ValueError('endpoint receipt not bound to full after catalog')
  if r['owner']!='postgres' or r['lanname']!=('plpgsql' if r['nspname']=='private' else 'sql') or r['acl']!=acl or r['comment_sha256']!=EMPTY_SHA or r['catalog']!=expected[r['nspname']]:raise ValueError('guide source/owner/language/ACL/catalog differs from exact seal')
 return {'contract':'known_guide_two_function_delta_v1','status':'known_two_functions_only','before_sha256':approved_before_sha,'before_export_sha256':approved_before_export_sha,'after_export_sha256':export_sha(a),'endpoints_export_sha256':export_sha(receipt),'reviewed_binding_sha256':export_sha(reviewed_binding),'after_sha256':after['snapshot_sha256'],'before_function_count':len(old),'after_function_count':len(new),'added_functions':added,'seal_sha256':SEAL_SHA,'unchanged_document_runtime_sha256':DOC_RUNTIME_SHA,'production_applied_by_tool':False,'apply_authorized_by_tool':False,'next':'Root must independently review this proof, regenerate a separate guard capsule against this exact after capture with unchanged reviewed runtime, verify hashes, and retain previous capsules. Unknown differences STOP.'}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--before',required=True);p.add_argument('--after',required=True);p.add_argument('--endpoints',required=True);p.add_argument('--approved-proposal',required=True);p.add_argument('--seal',required=True);p.add_argument('--reviewed-after-binding',required=True);p.add_argument('--reviewed-after-binding-sha256',required=True);p.add_argument('--output',required=True);x=p.parse_args()
 def read(v):return json.loads(pathlib.Path(v).read_text())
 raw=pathlib.Path(x.seal).read_bytes()
 if hashlib.sha256(raw).hexdigest()!=SEAL_SHA:raise ValueError('immutable guide seal source changed')
 binding_raw=pathlib.Path(x.reviewed_after_binding).read_bytes()
 if not re.fullmatch('[a-f0-9]{64}',x.reviewed_after_binding_sha256) or hashlib.sha256(binding_raw).hexdigest()!=x.reviewed_after_binding_sha256:raise ValueError('reviewed after-binding file changed')
 marker=read(x.approved_proposal)['marker']
 proof=check(read(x.before),read(x.after),read(x.endpoints),json.loads(raw),marker['before_sha256'],marker['before_export_sha256'],json.loads(binding_raw))
 with pathlib.Path(x.output).open('x') as f:f.write(json.dumps(proof,indent=2)+'\n')
