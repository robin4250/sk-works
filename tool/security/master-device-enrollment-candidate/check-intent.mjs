// Isolated synthetic smoke test; this is not live GoTrue/device verification.
import { createRequire } from 'node:module';
const require = createRequire(process.cwd() + '/tool/security/fixture_dependencies/package.json');
const { PGlite } = require('@electric-sql/pglite');
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role;
 create schema auth; create schema private;
 create function auth.uid() returns uuid language sql as $$
   select '00000000-0000-0000-0000-000000000001'::uuid $$;
 create function public.is_current_user_master_admin() returns boolean
   language sql as $$ select true $$;
 create function private.require_reauthentication_session() returns uuid
   language sql as $$ select '00000000-0000-0000-0000-000000000002'::uuid $$;
 create table public.attempts(n int not null); insert into public.attempts values(0);
 create function public.verify_secondary_password(p text) returns boolean
   language plpgsql as $$ begin
     if p is distinct from 'synthetic-correct' then
       update public.attempts set n=n+1; return false;
     end if; return true;
   end $$;`);
await db.exec(await readFile(new URL('./enrollment-intent.sql.review-only', import.meta.url),'utf8'));
const call = `select public.prepare_master_device_enrollment_candidate($1,$2,$3) as result`;
const key='a'.repeat(64);
await assert.rejects(() => db.query(call,[key,'iphone','synthetic-correct']), /master_device_enrollment_unavailable/);
await db.exec('update master_device_enrollment_candidate.rollout set enabled=true');
let bad=await db.query(call,[key,'iphone','synthetic-wrong']);
assert.equal(bad.rows[0].result.accepted,false);
assert.equal((await db.query('select n from public.attempts')).rows[0].n,1);
for (const type of ['iphone','ipad','mac']) {
  const response=await db.query(call,[key,type,'synthetic-correct']);
  assert.equal(response.rows[0].result.accepted,true);
  assert.equal(response.rows[0].result.registration_complete,false);
}
await assert.rejects(() => db.query(call,[key,'mac','synthetic-correct']), /master_device_request_limit/);
await db.exec('update master_device_enrollment_candidate.rollout set enabled=false');
await assert.rejects(() => db.query(call,[key,'iphone','synthetic-correct']), /master_device_enrollment_unavailable/);
assert.equal((await db.query('select count(*)::int as n from master_device_enrollment_candidate.intents')).rows[0].n,3);
await db.close();
console.log('Synthetic intent smoke tests passed; enrollment is not production ready.');
