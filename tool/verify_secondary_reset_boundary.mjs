import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_SECONDARY_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_secondary_boundary_fixture')throw Error('Disposable loopback secondary boundary fixture only');
const client=new pg.Client({connectionString:url.href});await client.connect();
try {
 const version=(await client.query('show server_version_num')).rows[0].server_version_num;
 assert.ok(Number(version)>=170000&&Number(version)<180000,'PostgreSQL 17 fixture required');
 await client.query(`create extension pgcrypto;create schema auth;create role authenticated;create role anon;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,updated_at timestamptz);alter table public.user_secondary_credentials enable row level security;revoke all on public.user_secondary_credentials from public,authenticated,anon;`);
 await client.query(await fs.readFile(new URL('../supabase/tests/fixtures/secondary_reset_before.sql',import.meta.url),'utf8'));
 await client.query(`revoke all on function public.set_secondary_password(text),public.verify_secondary_password(text) from public,anon;grant execute on function public.set_secondary_password(text),public.verify_secondary_password(text) to authenticated;select set_config('test.uid','10000000-0000-0000-0000-000000000001',false);set role authenticated;select public.set_secondary_password('synthetic-initial');`);
 for(let i=0;i<5;i++)assert.equal((await client.query("select public.verify_secondary_password('synthetic-wrong') v")).rows[0].v,false);
 await assert.rejects(client.query("select public.verify_secondary_password('synthetic-initial')"),/temporarily locked/);
 // This reproduces the current API boundary; it is not a proposed lock bypass.
 await client.query("select public.set_secondary_password('synthetic-replacement')");
 assert.equal((await client.query("select public.verify_secondary_password('synthetic-replacement') v")).rows[0].v,true);
 assert.equal((await client.query("select public.verify_secondary_password('synthetic-initial') v")).rows[0].v,false);
 await client.query("select set_config('test.uid','10000000-0000-0000-0000-000000000002',false)");
 assert.equal((await client.query("select public.verify_secondary_password('synthetic-replacement') v")).rows[0].v,false,'another actor cannot verify the first actor credential');
 await client.query("select set_config('test.uid','',false)");await assert.rejects(client.query("select public.set_secondary_password('synthetic-replacement')"),/authentication required/);
 await client.query('reset role;set role anon');await assert.rejects(client.query("select public.set_secondary_password('synthetic-replacement')"),/permission denied/);await client.query('reset role');
 assert.equal((await client.query('select count(*)::int n from public.user_secondary_credentials')).rows[0].n,1);
 console.log('PASS PostgreSQL 17: attempt lock and actor/anonymous boundaries; current direct reset replaces existing credential without reauthentication proof. Synthetic fixture only; no production changes.');
}finally{await client.end();}
