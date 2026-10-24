#!/usr/bin/env python3
"""Offline exact-observation-bound SQL preparation. No connection or deployment."""
import argparse,hashlib,importlib.util,json,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[2]
INVENTORY=pathlib.Path(__file__).with_name('inventory.read-only.sql')
OWNED_COLS={'public.daily_report_workers':['company_allowance_selections','company_allowance_legacy_labels'],'public.attendance_entries':['company_allowance_receipt_id']}
OWNED_TRIGGERS=['company_checkout_receipt_pointer_guard','company_checkout_report_metadata_guard']
def literal(s):return "'"+s.replace("'","''")+"'"
def body(s):
 m=re.search(r'\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$',s,re.I)
 if not m:raise ValueError('routine body unavailable')
 return m[2]
def comparable(snapshot):
 s=json.loads(json.dumps(snapshot));s.pop('private_schema_present',None)
 for r in s['routines'].values():r.pop('definition',None)
 for name,cols in OWNED_COLS.items():
  s['relations'][name]['columns']=[x for x in s['relations'][name]['columns'] if x['name'] not in cols]
 s['trigger_catalog']=[x for x in s['trigger_catalog'] if x['name'] not in OWNED_TRIGGERS]
 return s

def guard(expected,label,ignore_added=()):
 inventory=INVENTORY.read_text().strip().rstrip(';')
 return '''do $bounded_guard$
declare actual jsonb;expected jsonb:=$bounded_expected$%s$bounded_expected$::jsonb;k text;cols jsonb;
begin
 select inventory into actual from (%s) q;
 actual:=actual-'private_schema_present';
 for k in select jsonb_object_keys(actual->'routines') loop
  actual:=jsonb_set(actual,array['routines',k],(actual#>array['routines',k])-'definition');
  if $ignored_added$%s$ignored_added$::jsonb?k then
   actual:=jsonb_set(actual,array['routines',k],expected#>array['routines',k]);end if;
 end loop;
 for k,cols in select key,value from jsonb_each($owned_cols$%s$owned_cols$::jsonb) loop
  actual:=jsonb_set(actual,array['relations',k,'columns'],(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(actual#>array['relations',k,'columns']) x where not cols? (x->>'name')));
 end loop;
 actual:=jsonb_set(actual,'{trigger_catalog}',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(actual->'trigger_catalog') x where not (x->>'name'=any(array['company_checkout_receipt_pointer_guard','company_checkout_report_metadata_guard']))));
 if actual is distinct from expected then raise exception 'Bounded checkout %s inventory differs; re-observe, do not blindly retry';end if;
end $bounded_guard$;
'''%(json.dumps(comparable(expected),separators=(',',':')),inventory,json.dumps(list(ignore_added)),json.dumps(OWNED_COLS),label)

def definitions(sql):
 pattern=r'create(?:\s+or\s+replace)?\s+function\s+([\w.]+)\(([^)]*)\)([\s\S]*?)\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*?)\4\s*;'
 result={}
 for m in re.finditer(pattern,sql,re.I):
  args=','.join(a.strip().split()[-1] for a in m[2].split(',')) if m[2].strip() else ''
  identity=m[1]+'('+args+')'
  result[identity]={'return_type':re.search(r'\breturns\s+(\w+)',m[3],re.I)[1].lower(),'argnames':[a.strip().split()[0] for a in m[2].split(',')] if m[2].strip() else None,'body_md5':hashlib.md5(m[5].encode()).hexdigest(),'definer':bool(re.search(r'security\s+definer',m[3],re.I)),'volatility':'i' if re.search(r'\bimmutable\b',m[3],re.I) else 's' if re.search(r'\bstable\b',m[3],re.I) else 'v'}
 return result

def added_guard(added,mode):
 lines=['do $added_guard$ begin']
 for identity,r in added.items():
  auth=identity.startswith('public.') or identity=='company_common_allowance_private.registered_labels(uuid)'
  service=identity=='public.read_daily_report_company_allowance_eligibility(uuid)'
  lines.append("if not exists(select 1 from pg_proc where oid=to_regprocedure("+literal(identity)+") and proowner='postgres'::regrole and md5(prosrc)="+literal(r['body_md5'])+" and prosecdef="+str(r['definer']).lower()+" and provolatile="+literal(r['volatility'])+" and not proisstrict and not proleakproof and proparallel='u' and prokind='f' and prorettype="+literal(r['return_type'])+"::regtype and proconfig=array['search_path=\"\"']) then raise exception 'added routine source/security differs: "+identity+"';end if;")
  lines.append("if has_function_privilege('anon',"+literal(identity)+",'EXECUTE') or has_function_privilege('authenticated',"+literal(identity)+",'EXECUTE') is distinct from "+str(auth).lower()+" or has_function_privilege('service_role',"+literal(identity)+",'EXECUTE') is distinct from "+str(service).lower()+" then raise exception 'added routine grant differs';end if;")
  allowed=["'postgres'::regrole"]+(["'authenticated'::regrole"] if auth else [])+(["'service_role'::regrole"] if service else [])
  lines.append("if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid="+literal(identity)+"::regprocedure and (a.grantee not in("+','.join(allowed)+") or a.grantor<>'postgres'::regrole or a.privilege_type<>'EXECUTE' or a.is_grantable)) then raise exception 'unexpected routine grantee';end if;")
 if mode=='integration':
  lines.append("if not exists(select 1 from pg_class where oid=to_regclass('company_checkout_allowance_private.receipts') and relowner='postgres'::regrole and relrowsecurity) or has_schema_privilege('authenticated','company_checkout_allowance_private','USAGE') or has_schema_privilege('service_role','company_checkout_allowance_private','USAGE') then raise exception 'private receipt security differs';end if;")
 if mode=='integration':
  for relation,cols in OWNED_COLS.items():
   for column in cols:
    typ='uuid' if column=='company_allowance_receipt_id' else 'text' if column=='company_allowance_legacy_labels' else 'jsonb'
    lines.append("if not exists(select 1 from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid="+literal(relation)+"::regclass and a.attname="+literal(column)+" and not a.attisdropped and a.atttypid="+literal(typ)+"::regtype and not a.attnotnull and d.oid is null) then raise exception 'owned public column catalog differs';end if;")
  lines.append("if exists(select 1 from pg_policy where polrelid='company_checkout_allowance_private.receipts'::regclass) or has_table_privilege('authenticated','company_checkout_allowance_private.receipts','SELECT') or has_table_privilege('service_role','company_checkout_allowance_private.receipts','SELECT') then raise exception 'private receipt access differs';end if;")
  for relation,name,fn in [('public.attendance_entries','company_checkout_receipt_pointer_guard','company_checkout_allowance_private.guard_receipt_pointer()'),('public.daily_report_workers','company_checkout_report_metadata_guard','company_checkout_allowance_private.guard_report_metadata()')]:
   lines.append("if not exists(select 1 from pg_trigger where tgrelid="+literal(relation)+"::regclass and tgname="+literal(name)+" and tgfoid="+literal(fn)+"::regprocedure and tgtype=23 and tgenabled='O' and tgqual is null and not tgisinternal) then raise exception 'owned trigger differs';end if;")
 lines.append('end $added_guard$;')
 return '\n'.join(lines)+'\n'

def main():
 p=argparse.ArgumentParser();p.add_argument('--snapshot',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--mode',choices=['integration'],default='integration');a=p.parse_args()
 before=json.loads(a.snapshot.read_text());assert before['schema']==1
 assert not before['private_schema_present']
 for relation,cols in OWNED_COLS.items():assert not any(x['name'] in cols for x in before['relations'][relation]['columns'])
 spec=importlib.util.spec_from_file_location('checkout_generator',ROOT/'tool/prepare_company_checkout_integration.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 sql,manifest=m.prepare();existing_patches=manifest['after_source_md5']
 for k,v in manifest['before_source_md5'].items():assert before['routines'][k]['source_md5']==v
 sql+='\n'+(ROOT/'docs/candidates/company_checkout_eligibility.sql.review-only').read_text()
 all_defs=definitions(sql);added={k:v for k,v in all_defs.items() if k not in existing_patches}
 for k in added:
  if k in before['routines']:assert not before['routines'][k]['present']
 after=json.loads(json.dumps(before))
 for k,v in existing_patches.items():after['routines'][k]['source_md5']=v
 # Remove only the known transaction wrappers. Keep every source/security guard.
 unit=re.sub(r'(?im)^begin;\s*','',sql);unit=re.sub(r'(?im)^commit;\s*','',unit)
 # The existing generator puts begin and SET on a single line; only its exact prefix is removed.
 unit=unit.replace("begin;set local lock_timeout='3s';set local statement_timeout='30s';", "set local lock_timeout='3s';set local statement_timeout='30s';")
 prefix="begin;set local lock_timeout='3s';set local statement_timeout='30s';\n"
 install=prefix+guard(before,'before')+unit+'\n'+guard(after,'after',added)+added_guard(added,a.mode)+'commit;\n'
 post=INVENTORY.read_text()
 restore=prefix+guard(after,'unused restore',added)+added_guard(added,a.mode)
 if a.mode=='integration':
  restore+="do $unused$ begin if exists(select 1 from company_checkout_allowance_private.receipts) or exists(select 1 from public.daily_report_workers where company_allowance_selections is not null or company_allowance_legacy_labels is not null) or exists(select 1 from public.attendance_entries where company_allowance_receipt_id is not null) then raise exception 'checkout already used; restore prohibited';end if;end $unused$;\n"
 for k in existing_patches:restore+=before['routines'][k]['definition'].rstrip(';\n')+';\n'
 if a.mode=='integration':
  restore+='drop trigger company_checkout_receipt_pointer_guard on public.attendance_entries;drop trigger company_checkout_report_metadata_guard on public.daily_report_workers;\n'
 for k in reversed(list(added)):restore+='drop function '+k+';\n'
 if a.mode=='integration':
  restore+='alter table public.attendance_entries drop column company_allowance_receipt_id;alter table public.daily_report_workers drop column company_allowance_selections,drop column company_allowance_legacy_labels;drop table company_checkout_allowance_private.receipts;drop schema company_checkout_allowance_private;\n'
 restore+=guard(before,'restored')+'commit;\n'
 a.output.mkdir(parents=True,exist_ok=False)
 for name,text in [('private-install.sql.review-only',install),('private-postflight.read-only.sql',post),('private-unused-restore.sql.review-only',restore)]:
  (a.output/name).write_text(text)
 metadata={'schema':1,'mode':a.mode,'production_connected':False,'deployment_performed':False,'application_data_mutations':False,'snapshot_sha256':hashlib.sha256(a.snapshot.read_bytes()).hexdigest(),'added_routines':added,'changed_routines':existing_patches,'artifacts':{name:hashlib.sha256((a.output/name).read_bytes()).hexdigest() for name in ['private-install.sql.review-only','private-postflight.read-only.sql','private-unused-restore.sql.review-only']}}
 (a.output/'prepare-status.json').write_text(json.dumps(metadata,indent=2)+'\n')
if __name__=='__main__':main()
