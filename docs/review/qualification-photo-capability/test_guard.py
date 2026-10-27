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
assert psql(session + 'select private.qualification_photo_upload_capability()').splitlines()[-1] == 't', 'active authorized member should be enabled'
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

