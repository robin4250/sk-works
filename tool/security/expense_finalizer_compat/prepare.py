#!/usr/bin/env python3
"""Offline exact-catalog binder. Never connects to a database."""
import argparse, hashlib, json, re
from pathlib import Path
OLD="22ff4377666ec56ccc4b261cf380e9c0"
NEW="26d214245ad95159dab04059710840bd"
UNIT_SHA="4589d3cb2ab90db9fb07120b04e938aaa95c386babfdd810ed0e47ea0ee98802"
TARGET="private.expense_cost_finalize()"
ROOT=Path(__file__).parent

def literal(s): return "'"+s.replace("'","''")+"'"
def block(name,body): return "do $"+name+"$\n"+body+"\n$"+name+"$;\n"
def digest(expr): return "encode(sha256(convert_to(("+expr+")::text,'UTF8')),'hex')"
def observer():
 s=(ROOT/"preflight.read-only.sql").read_text().strip().rstrip(';')
 return block("capture_finalizer_catalog", "declare c jsonb; old_path text:=current_setting('search_path');begin perform set_config('search_path','public, extensions',true);select checkpoint into c from ("+s+") observation; perform set_config('search_path',old_path,true);perform set_config('sko.finalizer_catalog',c::text,true);end")
def data_observer(relations):
 parts=[]
 for name in relations:
  parts += [literal(name), "(select jsonb_build_object('count',count(*),'rows_sha256',encode(sha256(convert_to(coalesce(string_agg(encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),'' order by encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex')),''),'UTF8')),'hex')) from "+name+" r)"]
 return "jsonb_build_object("+','.join(parts)+")"
def validate(before,unit):
 if hashlib.sha256(unit.encode()).hexdigest()!=UNIT_SHA: raise ValueError('reviewed candidate SQL differs')
 f=before['function']; a=f['attributes']
 if f['signature']!=TARGET or f['source_md5']!=OLD or f['owner']!='postgres': raise ValueError('target source/owner differs')
 if not a['prosecdef'] or a['provolatile']!='v' or a['proconfig']!=['search_path=""'] or a['pronargs']!=0: raise ValueError('target attributes differ')
 own=str(a['proowner'])
 if len(f['effective_acl'])!=1 or str(f['effective_acl'][0]['grantee'])!=own or str(f['effective_acl'][0]['grantor'])!=own or f['effective_acl'][0]['privilege_type']!='EXECUTE' or f['effective_acl'][0]['is_grantable']: raise ValueError('owner-only ACL differs')
 defs=[t for t in before['triggers'] if str(t['catalog']['tgfoid'])==str(a['oid'])]
 if not defs: raise ValueError('target trigger attachments missing')
 source=defs[0]['function_catalog']['prosrc']
 if hashlib.md5(source.encode()).hexdigest()!=OLD or source.count('new.revision')!=2: raise ValueError('exact source anchors differ')
 if hashlib.md5(source.replace('new.revision',"(row_data->>'revision')::integer").encode()).hexdigest()!=NEW: raise ValueError('patched source differs')
 if any(t['function_catalog']['prosrc']!=source for t in defs): raise ValueError('inconsistent target definitions')
 names=[r['name'] for r in sorted(before['relations'],key=lambda r:int(r['oid']))]
 if set(names)!={'invoices','payment_certificates','app_notifications','private.invoice_number_counters','private.expense_claims','private.expense_document_snapshots','private.expense_settlement_choices','private.expense_amount_consumptions'}: raise ValueError('protected relation inventory differs')
 allowed={'issue_graphql_placeholder','pgrst_ddl_watch','pgrst_drop_watch','issue_pg_cron_access','issue_pg_net_access','issue_pg_graphql_access'}
 if {e['catalog']['evtname'] for e in before['event_triggers']}!=allowed: raise ValueError('unreviewed event trigger inventory')
 return source, names

def normalized_current(before,source):
 # Only the target body/definition appears more than once in the full observer.
 oid=str(before['function']['attributes']['oid']); olddef=before['function']['definition']
 return """declare a jsonb:=current_setting('sko.finalizer_catalog')::jsonb; t jsonb; ts jsonb:='[]';begin
 if a#>>'{function,source_md5}' is distinct from %s then raise exception 'patched finalizer source differs';end if;
 a:=jsonb_set(jsonb_set(a,'{function,source_md5}',to_jsonb(%s::text)),'{function,definition}',to_jsonb(%s::text));
 for t in select value from jsonb_array_elements(a->'triggers') loop
  if t#>>'{catalog,tgfoid}'=%s then
   t:=jsonb_set(jsonb_set(t,'{function_catalog,prosrc}',to_jsonb(%s::text)),'{function_definition}',to_jsonb(%s::text));
  end if;ts:=ts||jsonb_build_array(t);
 end loop;
 a:=jsonb_set(a,'{triggers}',ts);
 if %s is distinct from %s then raise exception 'full original catalog differs';end if;
end""" % (literal(NEW),literal(OLD),literal(olddef),literal(oid),literal(source),literal(olddef),digest('a'),"SERVER_FINGERPRINT")

def prepare(before,unit,server_sha,mode):
 source,names=validate(before,unit)
 if mode=='fingerprint':
  return "begin transaction read only;set local statement_timeout='15s';set local search_path='';set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"+observer()+"select jsonb_build_object('sha256',"+digest("current_setting('sko.finalizer_catalog')::jsonb")+",'observation',current_setting('sko.finalizer_catalog')::jsonb) as fingerprint;rollback;\n"
 if not re.fullmatch('[0-9a-f]{64}',server_sha or ''): raise ValueError('independently observed PostgreSQL complete-catalog SHA required')
 norm=normalized_current(before,source).replace('SERVER_FINGERPRINT',literal(server_sha))
 prefix="-- PRIVATE REVIEW ONLY. Source-only operation; not a financial rollback.\nbegin;set local lock_timeout='3s';set local statement_timeout='30s';set local search_path='';set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"
 if mode=='postflight': return "begin transaction read only;set local search_path='';set local TimeZone='UTC';set local DateStyle='ISO, YMD';\n"+observer()+block('verify_installed_finalizer',norm)+"select jsonb_build_object('verified',true,'source_md5',"+literal(NEW)+",'application_data_mutated',false);rollback;\n"
 sql=prefix+block('require_finalizer_owner',"begin if current_user<>'postgres' then raise exception 'postgres installer required';end if;end")
 sql+="select pg_advisory_xact_lock(284017,1348);\n"
 # Names emitted by regclass may omit public depending on search_path of capture.
 qualified=[n if '.' in n else 'public.'+n for n in names]
 sql+='lock table '+','.join(qualified)+' in share mode;\n'+observer()
 if mode=='install':
  sql+=block('verify_finalizer_before',"begin if "+digest("current_setting('sko.finalizer_catalog')::jsonb")+" is distinct from "+literal(server_sha)+" then raise exception 'full finalizer checkpoint differs';end if;end")
 else: sql+=block('verify_finalizer_before_restore',norm)
 sql+=block('capture_finalizer_data',"begin perform set_config('sko.finalizer_data',("+data_observer(qualified)+")::text,true);end")
 sql+=unit+'\n' if mode=='install' else before['function']['definition'].rstrip(';')+';\n'
 sql+=observer()
 if mode=='install': sql+=block('verify_finalizer_after',norm)
 else: sql+=block('verify_finalizer_restored',"begin if "+digest("current_setting('sko.finalizer_catalog')::jsonb")+" is distinct from "+literal(server_sha)+" then raise exception 'restored full finalizer checkpoint differs';end if;end")
 sql+=block('verify_finalizer_data',"begin if "+data_observer(qualified)+" is distinct from current_setting('sko.finalizer_data')::jsonb then raise exception 'financial rows changed during source replacement';end if;end")
 return sql+'commit;\n'

def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['fingerprint','install','postflight','restore']);p.add_argument('--before',type=Path,required=True);p.add_argument('--unit',type=Path,required=True);p.add_argument('--postgres-sha256');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 result=prepare(json.loads(a.before.read_text()),a.unit.read_text(),a.postgres_sha256,a.mode)
 a.output.write_text(result);a.output.chmod(0o600)
if __name__=='__main__':main()
