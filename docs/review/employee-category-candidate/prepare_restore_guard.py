"""Generate an unused-only review candidate. Do not apply without native CI and catalog review."""
from pathlib import Path
import hashlib
import re
import argparse

parser=argparse.ArgumentParser()
parser.add_argument("--expected-installed-catalog-md5",required=True)
args=parser.parse_args()
if not re.fullmatch(r"[a-f0-9]{32}",args.expected_installed_catalog_md5):
 parser.error("reviewed installed catalog fingerprint required")

root=Path(__file__).parent
entries=[('private.apply_worker_personnel_payload(uuid,jsonb,uuid)','apply_worker_personnel_payload','55a6db4beb2111dca77ff666c7f58748'),('private.employee_personnel_view(uuid)','employee_personnel_view','092d2b58a18aae7cd91d599da4548d04'),('private.worker_personnel_payload(uuid)','worker_personnel_payload','834289a7ebeb762407181ea96107308f'),('public.save_worker_personnel_profile(uuid,jsonb)','save_worker_personnel_profile','662f1c4019e6143d25b8c783f7f49058'),('public.decide_worker_personnel_change(uuid,boolean)','decide','827bf6c1a807664b3c5f9d210c65280f')]
def digest(path):
 s=path.read_text(); m=re.search(r'AS (\$\w*\$)(.*?)\1',s,re.I|re.S)
 if not m: raise ValueError(path)
 return hashlib.md5(m.group(2).encode()).hexdigest()
def check(sig,h,attr):
 return f"if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('{sig}') and md5(p.prosrc)='{h}' and md5((to_jsonb(p)-'prosrc')::text)='{attr}') then raise exception 'employee_category_function_drift'; end if;\n"
tables=['public.companies','public.workers','public.worker_personnel_profiles','public.worker_family_members','employee_category_private.categories','employee_category_private.assignments','employee_category_private.audit']
s="-- REVIEW ONLY: unused rollback candidate; Native verification required.\nbegin;\nset local search_path=''; set local lock_timeout='5s'; set local statement_timeout='45s';\nlock table "+','.join(tables)+" in share row exclusive mode;\n"
s+="do $g$ begin if current_user <> 'postgres' then raise exception 'wrong_operator'; end if; if exists(select 1 from employee_category_private.categories) or exists(select 1 from employee_category_private.assignments) or exists(select 1 from employee_category_private.audit) then raise exception 'employee_category_used'; end if;\n"
for sig,name,attr in entries:
 s+=check(sig,digest(root/f'{name}.{"before" if name=="decide" else "after"}.sql'),attr)
catalog=(root/'unused-restore-catalog.sql').read_text().strip().removeprefix('select ').removesuffix(';')
s+="if ("+catalog+") <> '"+args.expected_installed_catalog_md5+"' then raise exception 'employee_category_installed_catalog_drift'; end if;\n"
s+='end $g$;\n'
for _,name,_ in entries:
 if name!='decide': s+=(root/f'{name}.before.sql').read_text().rstrip().rstrip(';')+';\n'
s+='drop function public.add_employee_category(uuid,text) restrict;\ndrop function public.list_employee_categories(uuid) restrict;\ndrop function public.ensure_employee_categories(uuid) restrict;\ndrop function employee_category_private.check_manage(uuid) restrict;\ndrop table employee_category_private.assignments restrict;\ndrop table employee_category_private.audit restrict;\ndrop table employee_category_private.categories restrict;\ndrop schema employee_category_private restrict;\n'
# Every drop uses RESTRICT. Unknown external dependencies abort the transaction.
# Identity sequence is internally owned by audit and drops with that table.
s+='commit;\n'
(root/'restore-unused.guarded.sql.review-only').write_text(s)
print('Unused-only restore generated with reviewed installed catalog. Native verification required; no database operation performed.')
