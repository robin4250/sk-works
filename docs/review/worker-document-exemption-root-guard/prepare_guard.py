#!/usr/bin/env python3
"""Prepare review-only exact guards from a root-captured read-only snapshot.
No network/database connection. Never applies generated SQL.
"""
import argparse,hashlib,json,pathlib,re,os
os.umask(0o077)
FUNCTIONS={
 'public.current_user_required_document_attention()',
 'private.require_reauthentication_session()', 'private.account_access_allowed()',
 'private.worker_document_exemption(text,jsonb)', 'public.worker_document_exemption(text,jsonb)',
}
BUSINESS={
 'public.companies','public.company_members','public.workers','public.document_requirements',
 'public.worker_document_statuses','public.worker_document_status_history','public.worker_private_bank_accounts',
}
NEW_TABLES={'private.worker_document_exemption_settings','private.worker_document_exemptions','private.worker_document_exemption_events'}
ADDED_FUNCTIONS={'private.worker_document_exemption(text,jsonb)','public.worker_document_exemption(text,jsonb)'}
NEEDLE='    and dr.is_required\n    and ('
PATCH='    and dr.is_required\n    and not exists (select 1 from private.worker_document_exemptions e\n      where e.company_id=v_company_id and e.worker_id=v_worker_id\n        and e.requirement_id=dr.id and e.active)\n    and ('
INSTALL_SHA256='585a8f71afbd542d06ae921e71fa10a9064a98b24c2a8db6fc0b7fe99a863ca1'
RESTORE_SHA256='657f3170a4eaed0ac7ee5053c29c4016d40dcf69be3706652a97813938e70c06'
def check(condition):
 if not condition: raise ValueError('Snapshot or candidate contract mismatch')
def sql(value): return "'"+str(value).replace("'","''")+"'"
def md5(s): return hashlib.md5(s.encode()).hexdigest()
def read(path):
 d=json.loads(path.read_text());d=d.get('snapshot',d)
 check(d.get('schema')==1 and set(d['functions'])==FUNCTIONS)
 check(set(d['business'])==BUSINESS and set(d['new_tables'])==NEW_TABLES)
 for row in d['business'].values():
  check(isinstance(row['count'],int) and row['count']>=0 and re.fullmatch('[0-9a-f]{32}',row['md5']))
 for key,row in d['functions'].items():
  if row['exists']:
   check(all(re.fullmatch('[0-9a-f]{32}',row[k]) for k in ('body_md5','attrs_md5')))
   check(row['definition'].startswith('CREATE OR REPLACE FUNCTION '))
 return d
def strip_transaction(s):
 check(len(re.findall(r'^begin;$',s,re.M))==1 and len(re.findall(r'^commit;$',s,re.M))==1)
 return re.sub(r'^commit;\s*$','',re.sub(r'^begin;\n','',s,count=1,flags=re.M),flags=re.M)
def function_guard(functions):
 checks=[]
 for name,row in sorted(functions.items()):
  if not row['exists']:
   checks.append(f"if to_regprocedure({sql(name)}) is not null then raise exception 'Unexpected function exists: {name}' using errcode='55000';end if;")
  else:
   checks.append(f"select * into p from pg_proc where oid=to_regprocedure({sql(name)});\nif not found or md5(p.prosrc) is distinct from {sql(row['body_md5'])} or md5((to_jsonb(p)-array['prosrc','probin','oid'])::text) is distinct from {sql(row['attrs_md5'])} then raise exception 'Function changed: {name}' using errcode='55000';end if;")
 return 'do $catalog$ declare p pg_proc%rowtype;begin\n'+'\n'.join(checks)+'\nend $catalog$;\n'
def row_guard(business):
 checks=[]
 for name,row in sorted(business.items()):
  checks.append(f"select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text) into n,h from {name} t;\nif n<>{row['count']} or h is distinct from {sql(row['md5'])} then raise exception 'Original rows changed: {name}' using errcode='55000';end if;")
 return 'do $rows$ declare n bigint;h text;begin\n'+'\n'.join(checks)+'\nend $rows$;\n'
def build_install(before,installer):
 check(all(not x for x in before['new_tables'].values()))
 check(all(not before['functions'][k]['exists'] for k in ADDED_FUNCTIONS))
 check(all(before['functions'][k]['exists'] for k in FUNCTIONS-ADDED_FUNCTIONS))
 attention=before['functions']['public.current_user_required_document_attention()']
 check(attention['security_definer'] is True and attention['owner']=='postgres')
 check(attention['definition'].count(NEEDLE)==1)
 new_definition=attention['definition'].replace(NEEDLE,PATCH)
 # pg_get_functiondef formatting remains unchanged after CREATE OR REPLACE;
 # extracting prosrc body from its preserved dollar delimiter is deterministic.
 body=re.search(r'AS (\$[^$]*\$)\n(.*)\1\n',new_definition,re.S)
 # The opening newline after delimiter is part of prosrc for existing functions.
 check(body)
 expected_body='\n'+body.group(2)
 result='-- ROOT REVIEW ONLY: exact before snapshot; candidate remains OFF.\nbegin;\nset local lock_timeout=\'5s\';\n'
 result+='lock table '+','.join(sorted(BUSINESS))+' in share mode;\n'
 result+=function_guard(before['functions'])+row_guard(before['business'])
 result+='do $absence$ begin\n'+'\n'.join(f"if to_regclass({sql(t)}) is not null then raise exception 'Candidate table already exists' using errcode='55000';end if;" for t in sorted(NEW_TABLES))+'\nend $absence$;\n'
 result+=strip_transaction(installer)+'\n'
 result+=row_guard(before['business'])
 result+=f"do $post$ declare p pg_proc%rowtype;begin select * into p from pg_proc where oid='public.current_user_required_document_attention()'::regprocedure;\nif md5(p.prosrc) is distinct from {sql(md5(expected_body))} or md5((to_jsonb(p)-array['prosrc','probin','oid'])::text) is distinct from {sql(attention['attrs_md5'])} then raise exception 'Attention postcondition failed' using errcode='55000';end if;\nif (select count(*) from private.worker_document_exemption_settings)<>1 or exists(select 1 from private.worker_document_exemption_settings where enabled) or exists(select 1 from private.worker_document_exemptions) or exists(select 1 from private.worker_document_exemption_events) then raise exception 'Candidate did not install unused/OFF' using errcode='55000';end if;\nend $post$;\ncommit;\n"
 return result

def build_restore(before,after,raw):
 check(after['business']==before['business'])
 check(all(after['new_tables'].values()) and all(x['exists'] for x in after['functions'].values()))
 result='-- ROOT REVIEW ONLY: exact installed catalog. Reject after any usage.\nbegin;\nset local lock_timeout=\'5s\';\n'
 result+='lock table '+','.join(sorted(BUSINESS))+' in share mode;\n'
 result+=function_guard(after['functions'])+row_guard(after['business'])
 result+=strip_transaction(raw)+'\n'
 result+=function_guard(before['functions'])+row_guard(before['business'])
 result+='do $absence$ begin\n'+'\n'.join(f"if to_regclass({sql(t)}) is not null then raise exception 'Candidate table still exists' using errcode='55000';end if;" for t in sorted(NEW_TABLES))+'\nend $absence$;\ncommit;\n'
 return result
p=argparse.ArgumentParser();p.add_argument('--before',required=True,type=pathlib.Path);p.add_argument('--after',type=pathlib.Path);p.add_argument('--candidate-dir',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);args=p.parse_args()
before=read(args.before);args.output.mkdir(parents=True,exist_ok=True)
installer=(args.candidate_dir/'install.sql.review-only').read_text()
check(hashlib.sha256(installer.encode()).hexdigest()==INSTALL_SHA256)
if args.after:
 raw_restore=(args.candidate_dir/'restore-unused.sql.review-only').read_text()
 check(hashlib.sha256(raw_restore.encode()).hexdigest()==RESTORE_SHA256)
 out=build_restore(before,read(args.after),raw_restore);name='restore-unused.guarded.sql.review-only'
else:
 out=build_install(before,installer);name='install-off.guarded.sql.review-only'
(args.output/name).write_text(out)
print(json.dumps({'file':name,'sha256':hashlib.sha256(out.encode()).hexdigest(),'applied':False}))
