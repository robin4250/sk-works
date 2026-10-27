"""Synthetic PostgreSQL only. Run after native-install-guard-test.py in the same DB."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).parent
psql = ['psql', '-X', '-v', 'ON_ERROR_STOP=1']

def query(sql):
    return subprocess.check_output(psql + ['-Atc', sql], text=True).strip()

def execute(sql):
    subprocess.run(psql + ['-c', sql], check=True)

catalog = query((root/'unused-restore-catalog.sql').read_text())
assert re.fullmatch('[a-f0-9]{32}', catalog)
subprocess.run([sys.executable, str(root/'prepare_restore_guard.py'),
                '--expected-installed-catalog-md5', catalog], check=True)
source = (root/'restore-unused.guarded.sql.review-only').read_text()
pattern = r"to_regprocedure\('([^']+)'\) and md5\(p.prosrc\)='([a-f0-9]+)' and md5\(\(to_jsonb\(p\)-'prosrc'\)::text\)='([a-f0-9]+)'"

def adapt(match):
    attr = query("select md5((to_jsonb(p)-'prosrc')::text) from pg_proc p where oid=to_regprocedure('" + match[1] + "')")
    return match[0].replace(match[3], attr)

source, count = re.subn(pattern, adapt, source)
assert count == 5

with tempfile.TemporaryDirectory(prefix='employee-restore-fixture-') as directory:
    path = Path(directory)/'restore.sql'
    path.write_text(source)
    def restore():
        return subprocess.run(psql+['-f', str(path)], capture_output=True, text=True)
    execute("insert into employee_category_private.audit(company_id,actor_id,action) values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','fixture')")
    result = restore()
    assert result.returncode and 'employee_category_used' in result.stderr
    assert query('select count(*) from employee_category_private.audit') == '1'
    # Fixture cleanup only; never part of production restore.
    execute('delete from employee_category_private.audit')
    execute('create view public.synthetic_employee_dependency as select * from employee_category_private.categories')
    result = restore()
    assert result.returncode, 'unknown dependency must reject restore'
    assert query("select to_regprocedure('public.add_employee_category(uuid,text)') is not null") == 't', 'failed restore must roll back function drops'
    execute('drop view public.synthetic_employee_dependency')
    result = restore()
    assert result.returncode == 0, result.stderr
    assert query("select to_regnamespace('employee_category_private') is null") == 't'
    result = restore()
    assert result.returncode, 'duplicate restore must reject'
print('unused restore, used refusal, unknown dependency rollback and duplicate refusal passed')
