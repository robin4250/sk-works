import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE_PATH||'@electric-sql/pglite');
const db=new PGlite();
const call=key=>db.query('select private.upsert_generation_setting_issue($1,$2,$3,$4,$5,$6,$7)',['10000000-0000-0000-0000-000000000001',key,'payroll','Fixture title','Fixture body','payroll_settings',null]);
const count=async()=>Number((await db.query('select count(*) as n from public.app_notifications')).rows[0].n);
try {
 await db.exec(fs.readFileSync('supabase/tests/generation_setting_issue_notification_fixture.sql','utf8'));
 await call('before');assert.equal(await count(),0,'captured original initial issue loses notification');
 await db.exec(fs.readFileSync('supabase/migrations/20261009205616_generation_setting_issue_first_notification.sql','utf8'));
 await call('after');assert.equal(await count(),1,'first issue reaches actual sink');
 await call('after');assert.equal(await count(),1,'active retry emits no additional notification');
 await db.exec("update public.generation_setting_issues set resolved_at=now() where issue_key='after'");
 await call('after');assert.equal(await count(),2,'resolved issue reopening emits one notification');
 await db.exec("create function private.fixture_reject_notification() returns trigger language plpgsql as $$begin raise exception 'fixture notification insert failure';end$$;create trigger fixture_reject_notification before insert on public.app_notifications for each row execute function private.fixture_reject_notification()");
 await assert.rejects(call('rollback'),/fixture notification insert failure/);
 assert.equal(Number((await db.query("select count(*) as n from public.generation_setting_issues where issue_key='rollback'")).rows[0].n),0,'notification failure rolls back initial issue');
 assert.equal(await count(),2);
 await db.exec("update public.generation_setting_issues set resolved_at=now() where issue_key='after'");
 await assert.rejects(call('after'),/fixture notification insert failure/);
 assert.equal((await db.query("select resolved_at is not null as resolved from public.generation_setting_issues where issue_key='after'")).rows[0].resolved,true,'notification failure rolls back reopening');
 console.log('PASS first creation / active retry / reopen / actual sink failure rollback. Concurrency needs native PG17.');
}finally{await db.close();}
