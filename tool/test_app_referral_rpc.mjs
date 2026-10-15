// Run with PGLITE_PACKAGE pointing to a pinned @electric-sql/pglite installation.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PACKAGE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create schema auth; create schema private;
create table auth.users(id uuid primary key);
create table public.companies(id uuid primary key,name text);
create table public.company_members(user_id uuid,company_id uuid,role text);
create table public.user_profiles(user_id uuid,display_name text);
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function private.account_access_allowed() returns boolean language sql as $$ select true $$;
create function public.is_current_user_master_admin() returns boolean language sql as $$ select coalesce(current_setting('test.master',true),'')='yes' $$;
grant usage on schema private,auth to authenticated;
`);
const migration = await fs.readFile(new URL('../supabase/migrations/20261015012003_app_referral_invites.sql', import.meta.url), 'utf8');
await db.exec(migration);
const owner='00000000-0000-0000-0000-000000000001';
const member='00000000-0000-0000-0000-000000000002';
const company='10000000-0000-0000-0000-000000000001';
await db.exec(`insert into auth.users values('${owner}'),('${member}'); insert into companies values('${company}','Test Company'); insert into company_members values('${owner}','${company}','owner'),('${member}','${company}','employee');`);
async function as(user, master=false) {
  await db.exec(`reset role; select set_config('test.uid','${user}',false); select set_config('test.master','${master?'yes':'no'}',false); set role authenticated;`);
}
async function rpc(sql) { return (await db.query(sql)).rows[0].result; }
await as(owner);
assert.equal((await rpc('select public.app_referral_snapshot() result')).can_invite,false);
await assert.rejects(()=>db.query(`select public.app_referral_prepare('Example','09012345678')`),/disabled/);
await as(owner,true);
await db.query(`select public.app_referral_save_settings(true,false,true,'https://testflight.apple.com/join/ABCD1234')`);
const invitation=await rpc(`select public.app_referral_prepare('Example','+81 90-1234-5678') result`);
assert.equal(invitation.phone,'09012345678');
assert.ok(invitation.message.includes(invitation.id));
await db.query(`select public.app_referral_composer_opened('${invitation.id}')`);
const own=await rpc('select public.app_referral_snapshot() result');
assert.match(own.invitations[0].state_label,/送信・配達未確認/);
assert.equal(own.invitations[0].registered_user_id,null);
assert.equal(own.invitations[0].points,null);
await as(member);
assert.equal((await rpc('select public.app_referral_snapshot() result')).invitations.length,0);
await assert.rejects(()=>db.query(`select public.app_referral_prepare('Example','09012345678')`),/disabled/);
await assert.rejects(()=>db.query('select public.app_referral_master_snapshot()'),/master/);
await assert.rejects(()=>db.query(`select public.app_referral_composer_opened('${invitation.id}')`),/disabled/);
await assert.rejects(()=>db.query('select * from private.app_referral_invitations'),/permission denied/);
await as(owner,true);
await assert.rejects(()=>db.query(`select public.app_referral_save_settings(true,true,true,'https://example.com')`),/invalid distribution/);
await db.query(`select public.app_referral_save_settings(true,true,false,'https://testflight.apple.com/join/ABCD1234')`);
await as(member);
await assert.rejects(()=>db.query(`select public.app_referral_composer_opened('${invitation.id}')`),/unavailable/);
await rpc(`select public.app_referral_prepare('Another','08012345678') result`);
await as(owner,true);
const all=await rpc('select public.app_referral_master_snapshot() result');
assert.equal(all.invitations.length,2);
assert.equal(all.notify_master,false);
assert.equal(all.attribution_connected,false);
assert.ok(all.rankings.every(row=>Number(row.registration_count)===0 && row.points===null));
console.log('App referral RPC: feature gate, owner isolation, master access, URL validation, honest delivery state, no client attribution/points passed.');
await db.close();
