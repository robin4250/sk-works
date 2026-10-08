import fs from 'node:fs';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
try {
  await db.exec(`
    create schema auth; create schema private;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
    create function private.account_access_allowed() returns boolean language sql as $$ select coalesce(current_setting('test.blocked',true),'false') <> 'true' $$;
    create table company_members(company_id uuid,user_id uuid,role text);
    alter table company_members enable row level security;
    create policy own_membership on company_members for select to authenticated using(user_id=auth.uid());
    grant select on company_members to authenticated;
    grant usage on schema auth,private to authenticated;
    insert into company_members values
      ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000011','viewer'),
      ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000011','owner');
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20261008160834_attendance_rollout_capabilities.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/tests/attendance_rollout_capabilities_assertions.sql','utf8'));
  console.log('PASS read-only staged rollout capabilities: absent/default/OFF, partial installation, company/account boundaries and private ACLs');
} catch (error) { console.error(error.message, error.where ?? ''); process.exitCode = 1; }
finally { await db.close(); }
