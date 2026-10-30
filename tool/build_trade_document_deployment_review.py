"""Offline review bundle only. No database or network access; never applies SQL."""
import json, hashlib, pathlib, re, argparse

def read_json(path):
    value=json.loads(pathlib.Path(path).read_text())
    if isinstance(value,dict) and 'content' in value:
        raw=json.loads(value['content'][0]['text'])['result']
        fragment=raw[raw.index('['):raw.rindex(']')+1]
        try:value=json.loads(fragment)
        except json.JSONDecodeError:value=json.loads(fragment.replace('\\"','"').replace('\\\\','\\'))
    return value

def literal(value):
    text=json.dumps(value,ensure_ascii=False,separators=(',',':'),sort_keys=True)
    tag='$review_'+hashlib.sha256(text.encode()).hexdigest()[:16]+'$'
    assert tag not in text
    return tag+text+tag+'::jsonb'

def key(row): return row['schema']+'.'+row.get('name',row.get('proname',''))+'('+row.get('identity',row.get('arguments',''))+')'
def normalize(row):
    row=dict(row);row['name']=row.get('name',row.get('proname'));row['identity']=row.get('identity',row.get('arguments'))
    row['attributes']=dict(row['attributes'])
    # Catalog exports may intentionally keep the body only in the complete
    # pg_get_functiondef. Normalize both capture shapes exactly once; never
    # compare a prosrc-less object against full to_jsonb(pg_proc).
    body=re.search(r'\bAS (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1',row['definition'])
    assert body is not None, 'Unsupported non-dollar-quoted captured definition'
    source=body[2]
    assert hashlib.md5(source.encode()).hexdigest()==row['source_md5'], 'Captured definition/source digest differs'
    if 'prosrc' in row['attributes']:assert row['attributes']['prosrc']==source, 'Captured body copies differ'
    row['attributes']['prosrc']=source
    return {k:row[k] for k in ['schema','name','identity','definition','source_md5','attributes']}

def without_wrapper(source):
    lines=source.splitlines(keepends=True)
    begin=[i for i,l in enumerate(lines) if l.strip().lower()=='begin;']
    commit=[i for i,l in enumerate(lines) if l.strip().lower()=='commit;']
    assert len(begin)==len(commit)==1 and begin[0]<commit[0], 'Exactly one pinned transaction wrapper required'
    for index in sorted(begin+commit,reverse=True):del lines[index]
    return ''.join(lines)

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--formal-catalog',required=True);parser.add_argument('--hub-catalog',required=True)
parser.add_argument('--expected-fixture',required=True);parser.add_argument('--formal-root',required=True)
parser.add_argument('--hub-root',required=True);parser.add_argument('--output',required=True)
a=parser.parse_args();out=pathlib.Path(a.output);out.mkdir(exist_ok=True,parents=True)
formal=read_json(a.formal_catalog)
hub=read_json(a.hub_catalog)[0]['metadata']
assert len(formal)==3 and len(hub['functions'])==8
before={}
for r in hub['functions']+formal:
    r=normalize(r);k=key(r)
    if k in before:assert before[k]==r,'Shared profile captures differ'
    before[k]=r
assert len(before)==10
expected=[normalize(r) for r in read_json(a.expected_fixture)]
assert len(expected)==13
pins=[
 ('C',pathlib.Path(a.hub_root)/'docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only','dffcc373801fb2d4b56d0c128e406b8fbe8c9b0d7929087a4fd29e38b655c706'),
 ('terms',pathlib.Path(a.formal_root)/'docs/review/trade-document-terms/save-guard.sql.review-only','e5967ad6b5d54f413ba7db94887423f1f5c98057cafae6c1abed318ce171da5a'),
 ('v1',pathlib.Path(a.formal_root)/'docs/review/trade-document-form-input/server-save.sql.review-only','d57918a806b72e0d52299a3e175c9841258eaa71ce18f2abaab0a7877bd62178'),
 ('v2',pathlib.Path(a.formal_root)/'docs/review/trade-document-month-end/server-upgrade.sql.review-only','bc53ac3daa85452c032d2e2880ca334fe1ce4aee4601cf9cc0be9c6d09818a79')]
sources=[]
for label,path,digest in pins:
    data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==digest,(label,'Source changed')
    sources.append(without_wrapper(data.decode()))
# A fresh catalog is data, never code: it is quoted JSON and compared, not executed.
pre=literal([{k:v for k,v in r.items() if k!='definition'} for r in before.values()]);post=literal([{**{k:v for k,v in r.items() if k!='definition'},'language':re.search(r'LANGUAGE ([a-z0-9_]+)',r['definition'])[1]} for r in expected]);table=literal(hub['table']);constraints=literal(hub['constraints'])
old_check=next(c for c in hub['constraints'] if c['attributes']['conname']=='master_feature_settings_feature_key_check')
new_check_definition=old_check['definition'].replace("'traffic_bus_stop'::text","'traffic_bus_stop'::text, 'site_order_documents'::text")
assert new_check_definition!=old_check['definition']
check_definition=literal(new_check_definition)

sql='''-- REVIEW ONLY. Not authorized for production. No activation or business DML.
-- Atomic composition; reviewed source bodies below are SHA256 pinned by offline generator.
begin;
set local lock_timeout='3s';set local statement_timeout='60s';
'''
sql+=f'create temporary table reviewed_old_functions on commit drop as select value item from jsonb_array_elements({pre});\n'
sql+=f'create temporary table reviewed_expected_after on commit drop as select value item from jsonb_array_elements({post});\n'
sql+=f'create temporary table reviewed_master_table on commit drop as select {table} item;\n'
sql+=f'create temporary table reviewed_master_constraints on commit drop as select value item from jsonb_array_elements({constraints});\n'
sql+=f'''do $preflight$ declare e jsonb;p pg_proc;t jsonb;begin
 for e in select item from reviewed_old_functions loop
  select q.* into p from pg_proc q join pg_namespace n on n.oid=q.pronamespace
   where n.nspname=e->>'schema' and q.proname=e->>'name' and pg_get_function_identity_arguments(q.oid)=e->>'identity';
  if not found or to_jsonb(p) is distinct from e->'attributes'
   or md5(p.prosrc) is distinct from e->>'source_md5' then raise exception 'Fresh full function catalog changed; stop' using errcode='55000';end if;
 end loop;
 select to_jsonb(c) into t from pg_class c where c.oid='private.master_feature_settings'::regclass;
 if t is distinct from (select item from reviewed_master_table) then raise exception 'Fresh full master table catalog changed; stop' using errcode='55000';end if;
 if (select coalesce(jsonb_agg(jsonb_build_object('attributes',to_jsonb(c),'definition',pg_get_constraintdef(c.oid)) order by c.oid),'[]'::jsonb) from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass) is distinct from
  (select coalesce(jsonb_agg(value order by (value#>>'{{attributes,oid}}')::oid),'[]'::jsonb) from (select item value from reviewed_master_constraints) reviewed)
  then raise exception 'Fresh master constraints changed; stop' using errcode='55000';end if;
 if to_regprocedure('private.save_trade_document_before_confirmed_terms(text,uuid,text,integer,jsonb)') is not null
  or to_regprocedure('private.save_trade_document_before_form_fields(text,uuid,text,integer,jsonb)') is not null
  or to_regprocedure('private.validate_trade_document_form_fields(jsonb)') is not null then
  raise exception 'Formal predecessor already present; reconcile, never retry blindly' using errcode='55000';end if;
end $preflight$;
'''
# Retain the actual observed old OIDs for checks after deliberate saver renaming.
sql+='\n'.join('-- Exact source segment '+pins[i][0]+'\n'+s for i,s in enumerate(sources))
sql+=f'''
do $postflight$ declare e jsonb;p pg_proc;want jsonb;old jsonb;new_check pg_constraint;expected_oid oid;lang text;counted integer:=0;begin
 for e in select item from reviewed_expected_after loop
  select q.* into p from pg_proc q join pg_namespace n on n.oid=q.pronamespace
   where n.nspname=e->>'schema' and q.proname=e->>'name' and pg_get_function_identity_arguments(q.oid)=e->>'identity';
  if not found then raise exception 'Expected installed function missing' using errcode='55000';end if;
  -- OIDs of newly added functions are allocated at installation. All other
  -- pg_proc attributes are compared in full after resolving cluster-local IDs.
  lang:=e->>'language';
  want:=(e->'attributes')||jsonb_build_object('oid',to_jsonb(p.oid),
   'pronamespace',to_jsonb(to_regnamespace(e->>'schema')::oid),
   'proowner',to_jsonb((select oid from pg_roles where rolname='postgres')),
   'prolang',to_jsonb((select oid from pg_language where lanname=lang)));
  if to_jsonb(p) is distinct from want or md5(p.prosrc) is distinct from e->>'source_md5'
   then raise exception 'Installed full function attributes/source differ' using errcode='55000';end if;
  select item into old from reviewed_old_functions where item->>'schema'=e->>'schema' and item->>'name'=e->>'name' and item->>'identity'=e->>'identity';
  if old is not null and e->>'name'<>'save_trade_document_attachment' and p.oid is distinct from (old#>>'{{attributes,oid}}')::oid then
   raise exception 'Existing function OID changed' using errcode='55000';end if;
  if e->>'name'='save_trade_document_before_confirmed_terms' then
   select (item#>>'{{attributes,oid}}')::oid into expected_oid from reviewed_old_functions where item->>'schema'='private' and item->>'name'='save_trade_document_attachment';
   if p.oid is distinct from expected_oid then raise exception 'Original saver delegate identity changed' using errcode='55000';end if;
  end if;
  counted:=counted+1;
 end loop;
 if counted<>13 then raise exception 'Installed scope count changed';end if;
 -- Dependencies that are not part of the requested change remain fully exact.
 for old in select item from reviewed_old_functions where item->>'name' in ('is_current_user_master_admin','require_reauthentication_session','consume_reauthentication_proof','account_access_allowed','set_master_feature_enabled') loop
  select q.* into p from pg_proc q where q.oid=(old#>>'{{attributes,oid}}')::oid;
  if not found or to_jsonb(p) is distinct from old->'attributes' then
   raise exception 'Unrelated authorization dependency changed' using errcode='55000';end if;
 end loop;
 if (select to_jsonb(c) from pg_class c where c.oid='private.master_feature_settings'::regclass) is distinct from (select item from reviewed_master_table)
  then raise exception 'Master table full identity/security changed' using errcode='55000';end if;
 if (select count(*) from pg_constraint where conrelid='private.master_feature_settings'::regclass)<>(select count(*) from reviewed_master_constraints) then raise exception 'Master constraint count changed';end if;
 for e in select item from reviewed_master_constraints loop
  if e#>>'{{attributes,conname}}'='master_feature_settings_feature_key_check' then
   select c.* into new_check from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass and c.conname='master_feature_settings_feature_key_check';
   if not found or (to_jsonb(new_check)-'conbin') is distinct from (((e->'attributes')-'conbin')||jsonb_build_object('oid',to_jsonb(new_check.oid)))
    or pg_get_constraintdef(new_check.oid) is distinct from ({check_definition}#>>'{{}}') then raise exception 'Expected additive master CHECK differs';end if;
  elsif not exists(select 1 from pg_constraint c where to_jsonb(c)=e->'attributes' and pg_get_constraintdef(c.oid)=e->>'definition') then
   raise exception 'Unrelated master constraint changed';
  end if;
 end loop;
 if exists(select 1 from private.master_feature_settings where feature_key='site_order_documents' and enabled) then
  raise exception 'Installation must remain OFF' using errcode='55000';end if;
end $postflight$;
-- Capture this complete result after COMMIT/readback into the private receipt.
select n.nspname schema,p.proname name,pg_get_function_identity_arguments(p.oid) identity,
 pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p) attributes
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where exists(select 1 from (select item e from reviewed_expected_after) reviewed where e->>'schema'=n.nspname and e->>'name'=p.proname and e->>'identity'=pg_get_function_identity_arguments(p.oid)) order by n.nspname,p.proname;
commit;
'''
(out/'atomic-forward.sql.review-only').write_text(sql)
(out/'captured-before-functions.json').write_text(json.dumps(list(before.values()),ensure_ascii=False,indent=2)+'\n')
plan={'status':'REVIEW ONLY; production HOLD; no execution performed','sources':[{'stage':label,'path':str(path),'sha256':digest} for label,path,digest in pins],'fresh_captured_function_count':len(before),'expected_modified_or_additive_scope':len(expected),'preflight':'Full pg_proc+definition match of 10 fresh functions; full pg_class and all original constraints; exact source pins; no preexisting formal delegates/validator','postflight':'Full pg_proc semantic attributes of 13 functions with cluster-local OID resolution; original source/profile/C public OIDs retained; original saver OID retained under before_confirmed_terms; 5 unchanged auth dependencies full exact; master table full exact; site_order_documents OFF','business_dml':'No business DML at installation. No template/attachment/financial/signature/flag row changes. SQL function body text contains existing runtime DML but no such function is invoked by installation.','activation':'Not included; existing automatic appendix preferences unchanged; individual exemption untouched','rollback_before_commit':'A failing guard rolls back the single transaction. Lost commit ACK requires read-only reconciliation; no blind retry.','restore_after_commit':{'status':'Separate stopped-writer operation, not an automatic undo; exact committed full receipt required','targets':['public.current_master_feature_flags()','public.set_master_feature_enabled_with_proof(text,boolean,text)','private.trade_document_source(text,uuid,text)','private.partner_company_profile_value(uuid)','private.save_trade_document_attachment(text,uuid,text,integer,jsonb)'],'preserve':['Additive CHECK/new guarded functions','All OFF feature rows','Original saver under before_confirmed_terms and intermediate before_form_fields delegate','Every attachment/PDF/signature/financial row'],'require':['Operational writer stop plus in-flight completion; feature OFF alone is not enough','Exact complete committed pg_proc receipt and dependent-source check','No saved attachment carrying contract_terms or form_fields; any such receipt blocks old saver restoration, including schema1','Original source/profile/C public bodies preserve their OIDs; restored current saver keeps its newly allocated OID; do not claim full identity rollback','Do not DROP functions, contract CHECK, rename away current saver or delete rows','If any new terms/form receipt exists, retain guarded writers and repair forward under separate review']},'atomic_forward_sha256':hashlib.sha256(sql.encode()).hexdigest()}
(out/'review-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'review bundle generated, not applied','before_functions':len(before),'after_scope':len(expected),'sql_sha256':plan['atomic_forward_sha256']}))
