from pathlib import Path
import subprocess
import os
import re

base = Path('docs/review/qualification-photo-capability')
env = dict(os.environ)
def psql(sql):
    return subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-At'],
                          input=sql, text=True, env=env, capture_output=True, check=True).stdout.strip()
psql((base / 'fixture.sql').read_text())
psql((base / 'source-before.sql.review-only').read_text() + ';')
session = "select set_config('test.actor','00000000-0000-0000-0000-000000000001',false); select set_config('test.account','true',false); "
assert psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1] == 'f', 'old function must fail closed with new unrelated policies'
meta = psql("select md5((to_jsonb(p)-'prosrc')::text) from pg_proc p where p.oid='private.qualification_photo_upload_capability()'::regprocedure")
install = (base / 'install.guarded.sql.review-only').read_text()
assert 'd6d019eefbe8495b2006a8d36a0b367a' in install and '1e50d68e375a7b9ad4579ae4c9417306' in install
install = install.replace('1e50d68e375a7b9ad4579ae4c9417306', meta)
psql(install)
actual = psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1]
if actual != 't':
    print(psql("select polname || ':' || pg_get_expr(polwithcheck,polrelid) from pg_policy where polrelid='storage.objects'::regclass and not polpermissive order by polname"))
    print(psql(session + "select auth.uid(),private.account_access_allowed(),(select count(*) from public.workers w join public.company_members m on w.company_id=m.company_id and w.user_id=m.user_id where w.user_id=auth.uid() and w.status='active')"))
assert actual == 't', 'active authorized member should be enabled'
psql(session + "set role authenticated; insert into storage.objects(bucket_id,name) values ('qualification-certificates','draft/approved.jpg'); reset role;")
try:
    psql(session + "set role authenticated; insert into storage.objects(bucket_id,name) values ('qualification-certificates','draft/unauthorized.jpg');")
    raise AssertionError('unprepared qualification upload should be rejected by RLS')
except subprocess.CalledProcessError as error:
    assert 'row-level security' in error.stderr, error.stderr
assert psql("select private.qualification_photo_upload_capability()") == 'f', 'anonymous must be rejected'
assert psql(session + "select set_config('test.account','false',false); select private.qualification_photo_upload_capability()").splitlines()[-1] == 'f', 'restricted account must be rejected'
psql("create policy unreviewed_restrictive on storage.objects as restrictive for insert to authenticated with check (true)")
assert psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1] == 'f', 'unknown restrictive policy must fail closed'
psql("drop policy unreviewed_restrictive on storage.objects")
psql("drop policy custom_chat_photo_insert_boundary on storage.objects")
psql("create policy custom_chat_photo_insert_boundary on storage.objects as restrictive for insert to authenticated with check (true)")
assert psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1] == 'f', 'changed known policy must fail closed'
psql('drop policy custom_chat_photo_insert_boundary on storage.objects')
restore = (base / 'restore.guarded.sql.review-only').read_text().replace('1e50d68e375a7b9ad4579ae4c9417306', meta)
psql(restore)
assert psql("select md5(prosrc) from pg_proc where oid='private.qualification_photo_upload_capability()'::regprocedure") == 'd6d019eefbe8495b2006a8d36a0b367a'
assert psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1] == 'f', 'restore must reinstate old behavior'
print('PASS: old/new/restore, authenticated, account, anonymous, unknown and changed policy')

