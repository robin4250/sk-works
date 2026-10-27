"""Fixture-only test. Production catalog hashes are changed only in this test copy."""
from pathlib import Path
import re, subprocess, tempfile
root=Path(__file__).parent
psql=['psql','-X','-v','ON_ERROR_STOP=1']
for name in ['apply_worker_personnel_payload','employee_personnel_view','worker_personnel_payload','save_worker_personnel_profile','decide']:
 subprocess.run(psql+['-f',str(root/(name+'.before.sql'))],check=True)
s=(root/'install.guarded.sql.review-only').read_text()
assert len(re.findall(r'^begin;\s*$',s,re.M|re.I))==1,'must have one transaction boundary'
assert len(re.findall(r'^commit;\s*$',s,re.M|re.I))==1
pattern=r"to_regprocedure\('([^']+)'\) and md5\(p.prosrc\)='([a-f0-9]+)' and md5\(\(to_jsonb\(p\)-'prosrc'\)::text\)='([a-f0-9]+)'"
def adapt(m):
 sig=m.group(1)
 q="select md5((to_jsonb(p)-'prosrc')::text) from pg_proc p where oid=to_regprocedure('"+sig+"')"
 attr=subprocess.check_output(psql+['-Atc',q],text=True).strip()
 assert re.fullmatch('[a-f0-9]{32}',attr)
 return m.group(0).replace(m.group(3),attr)
s,n=re.subn(pattern,adapt,s)
assert n==10
with tempfile.TemporaryDirectory(prefix='employee-guard-fixture-') as d:
 f=Path(d)/'install.sql';f.write_text(s)
 subprocess.run(psql+['-f',str(f)],check=True)
 again=subprocess.run(psql+['-f',str(f)],capture_output=True,text=True)
 assert again.returncode!=0 and 'employee_category_exists' in again.stderr,'second install must reject'
q="select count(*) from employee_category_private.categories"
assert subprocess.check_output(psql+['-Atc',q],text=True).strip()=='0','install must not initialize or assign employees'
print('guard install, single transaction, duplicate refusal and empty categories verified on synthetic database')
