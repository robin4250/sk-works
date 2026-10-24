"""Generate exact-source review DDL only. No connection or application writes."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FILES=[
 'docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only',
 'docs/candidates/trade_document_invoice_confirmation_20261021.sql.review-only',
 'docs/candidates/trade_document_monthly_review_20261022.sql.review-only',
 'docs/candidates/trade_document_confirmation_api_20261022.sql.review-only']
SIGNATURES={
 'trade_document_consent_private.prepare_document':'uuid,uuid,uuid,integer,jsonb,text,uuid,text,integer',
 'trade_document_consent_private.decide':'uuid,integer,uuid,integer,text,text,text,boolean,uuid',
 'trade_document_consent_private.confirm_local_document':'uuid,uuid,integer,jsonb,uuid,boolean,boolean',
 'trade_document_consent_private.confirm_monthly_review':'uuid,uuid,integer,jsonb,uuid,boolean,boolean',
 'trade_document_confirmation_api_private.workspace':'text,uuid,text',
 'trade_document_confirmation_api_private.confirm':'jsonb,uuid,boolean,boolean'}
PAT=re.compile(r'(?im)^create(?: or replace)? function (?P<name>[\w.]+)\((?P<args>.*?)\)(?P<header>.*?)\bas\s+(?P<tag>\$[A-Za-z_]*\$)(?P<body>.*?)(?P=tag);',re.S)
def once(s,old,new):
 if s.count(old)!=1:raise ValueError('exact source anchor mismatch')
 return s.replace(old,new,1)
def main():
 manifest=json.loads((ROOT/'tool/fixtures/trade_reciprocal_gate/source_manifest.json').read_text());known={x['path']:x['sha'] for x in manifest['files']};defs={};sources={}
 for p in FILES:
  b=(ROOT/p).read_bytes();assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==known[p],p
  sources[p]=hashlib.sha256(b).hexdigest()
  for m in PAT.finditer(b.decode()):defs[m['name']]=(m.group(0),m['body'])
 rows=[];patched=[];proof=[]
 for name,args in SIGNATURES.items():
  full,body=defs[name];original=body
  if name.endswith('.prepare_document'):
   body=once(body,'perform trade_document_consent_private.require_actor(own_company);perform trade_document_consent_private.lock_pair(own_company,peer_company);','perform trade_document_consent_private.require_actor(own_company);\n perform trade_document_consent_private.require_gated_write_pair(own_company,peer_company,true);\n perform trade_document_consent_private.lock_pair(own_company,peer_company);')
  elif name.endswith('.decide'):
   body=once(body," if action='cancel' then", " perform trade_document_consent_private.require_gated_write_pair(cid,d.counterparty_company_id,action<>'cancel');\n if action='cancel' then")
  elif name.endswith('.workspace'):
   body=once(body,' perform 1 from public.companies where id in(cid,peer) order by id for update;', " begin perform trade_document_consent_private.require_gated_write_pair(cid,peer,true);\n exception when insufficient_privilege then return base||jsonb_build_object('integration_required',true,'unavailable_reason','connection_not_accepted');\n when object_not_in_prerequisite_state then\n  return base||trade_document_confirmation_api_private.resolve(kind,parent_id)||jsonb_build_object('can_integrated_confirm',false,'unavailable_reason','reciprocal_feature_disabled');\n end;\n perform 1 from public.companies where id in(cid,peer) order by id for update;")
  elif name.endswith('.confirm'):
   body=once(body,' perform 1 from public.companies where id in(cid,', " perform trade_document_consent_private.require_gated_write_pair(cid,(s->>'counterparty_company_id')::uuid,true);\n perform 1 from public.companies where id in(cid,")
  else:
   body=once(body,' perform 1 from public.companies where id in(d.issuer_company_id,d.counterparty_company_id) order by id for update;', ' perform trade_document_consent_private.require_gated_write_pair(cid,d.counterparty_company_id,true);\n perform 1 from public.companies where id in(d.issuer_company_id,d.counterparty_company_id) order by id for update;')
  before=hashlib.md5(original.encode()).hexdigest();after=hashlib.md5(body.encode()).hexdigest();api='confirmation_api_private' in name
  acl=['authenticated=X/postgres','postgres=X/postgres'] if api else ['postgres=X/postgres']
  rows.append("('%s(%s)','%s',array[%s]::text[])"%(name,args,before,','.join("'%s'"%x for x in acl)))
  patched.append(re.sub(r'^create(?: or replace)? function','create or replace function',full.replace(original,body,1),count=1,flags=re.I))
  proof.append({'signature':name+'('+args+')','before_md5':before,'after_md5':after})
 # Exact phase-A guard body, already Native-tested by its owner. Keep this source
 # text independent from the runtime financial/actor source; never install it here.
 guard="\ndeclare enabled_value boolean;\nbegin\n select enabled into enabled_value from private.master_feature_settings\n where feature_key='trade_document_reciprocal_seals' for share;\n if not found or enabled_value is not true then\n  raise exception using errcode='55000',message='trade reciprocal seals disabled';\n end if;\nend "
 gh=hashlib.md5(guard.encode()).hexdigest()
 sql="""-- REVIEW ONLY. Requires complete canonical trade units and phase A OFF.
-- No central toggle, proof lifecycle, stored stamp, PDF or application grant changes.
begin;
do $baseline$
begin
 if exists(select 1 from (values ROWS) expected(signature,body_md5,acl)
 left join pg_proc p on p.oid=to_regprocedure(expected.signature)
 where p.oid is null or md5(p.prosrc) is distinct from expected.body_md5
 or pg_get_userbyid(p.proowner) is distinct from 'postgres' or not p.prosecdef
 or p.prorettype<>'jsonb'::regtype or p.proretset or p.prokind<>'f' or p.prolang<>(select oid from pg_language where lanname='plpgsql')
 or p.proisstrict or p.proleakproof or p.provolatile<>'v' or p.proconfig is distinct from array['search_path=""']::text[]
 or array(select a::text from unnest(coalesce(p.proacl,acldefault('f',p.proowner))) a order by a::text) is distinct from expected.acl)
 then raise exception 'trade business baseline differs';end if;
 if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.require_trade_document_reciprocal_seals()')
 and md5(p.prosrc)='GUARDHASH' and pg_get_userbyid(p.proowner)='postgres' and not p.prosecdef
 and p.prorettype='void'::regtype and not p.proretset and p.prokind='f' and p.prolang=(select oid from pg_language where lanname='plpgsql')
 and not p.proisstrict and not p.proleakproof and p.provolatile='v' and p.proconfig=array['search_path=""']::text[]
 and array(select a::text from unnest(coalesce(p.proacl,acldefault('f',p.proowner))) a order by a::text)=array['postgres=X/postgres']::text[])
 or not exists(select 1 from private.master_feature_settings where feature_key='trade_document_reciprocal_seals' and enabled is false)
 or to_regprocedure('trade_document_consent_private.require_gated_write_pair(uuid,uuid,boolean)') is not null then
 raise exception 'exact phase A OFF prerequisite required';end if;
end $baseline$;
create function trade_document_consent_private.require_gated_write_pair(cid uuid,peer uuid,require_connection boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform trade_document_consent_private.require_actor(cid);
 if cid is null or peer is null or cid=peer or require_connection is null
 or (select count(*) from public.companies where id in(cid,peer))<>2 then raise exception 'exact company pair required' using errcode='42501';end if;
 if require_connection and (select count(*) from private.company_connections where status='accepted'
 and ((parent_company_id=cid and child_company_id=peer)or(parent_company_id=peer and child_company_id=cid)))<>1 then
 raise exception 'formal unique accepted company connection required' using errcode='42501';end if;
 perform private.require_trade_document_reciprocal_seals();
end $$;
revoke all on function trade_document_consent_private.require_gated_write_pair(uuid,uuid,boolean) from public,anon,authenticated,service_role;
""".replace('ROWS',',\n'.join(rows)).replace('GUARDHASH',gh)
 sql+='\n\n'.join(patched)+'\ncommit;\n'
 out=ROOT/'docs/candidates/trade_reciprocal_business_gate_20261024.sql.review-only';out.write_text(sql)
 (ROOT/'docs/candidates/trade_reciprocal_business_gate_20261024.manifest.json').write_text(json.dumps({'review_only':True,'main':manifest['main'],'source_sha256':sources,'phase_a_guard_md5':gh,'routines':proof,'output_sha256':hashlib.sha256(sql.encode()).hexdigest()},indent=2)+'\n')
if __name__=='__main__':main()
