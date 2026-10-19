import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_PACKAGE || '@electric-sql/pglite');
const sql = await readFile(process.env.SECURITY_COLLECTOR_SQL ||
  new URL('../../docs/candidates/security_collector_storage_v1_20261020.sql.review-only', import.meta.url), 'utf8');
const db = new PGlite();
let assertions = 0;
const checked = (condition, message) => { assert.ok(condition, message); assertions++; };
const q = async (s, args=[]) => (await db.query(s,args)).rows;
const deny = async (s,args=[]) => { await assert.rejects(()=>db.query(s,args)); assertions++; };
const role = async name => db.exec(`reset role; set role ${name}`);
const scalar = async (s,args=[]) => Object.values((await q(s,args))[0])[0];
try {
 await db.exec(`
 create role anon;create role authenticated;create role service_role bypassrls;
 create role sko_security_collector_ingest nologin noinherit;
 create schema private;create schema auth;
 grant usage on schema private,auth to authenticated;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('test.allowed',true),'false')='true'$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select coalesce(current_setting('test.master',true),'false')='true'$$;
 create table private.fixture_proofs(token text primary key,actor uuid not null,used boolean not null default false);
 create function private.consume_reauthentication_proof(op text,scope jsonb,proof text) returns void
 language plpgsql security definer set search_path='' as $$begin
 if op<>'master.security_collector.read' or scope<>'{"scope":"decoy_collector"}'::jsonb then raise exception 'wrong proof scope';end if;
 update private.fixture_proofs set used=true where token=proof and actor=auth.uid() and not used;
 if not found then raise exception 'invalid proof';end if;end $$;
 `);
 // Fail before creating objects for direct or transitive API-role membership,
 // or a privileged bridge. Candidate failure leaves a failed transaction;
 // explicitly roll it back before fixing the fixture prerequisite.
 await db.exec('grant sko_security_collector_ingest to authenticated');
 await assert.rejects(()=>db.exec(sql));assertions++;
 await db.exec('rollback;revoke sko_security_collector_ingest from authenticated');
 await db.exec('create role fixture_bridge;grant sko_security_collector_ingest to fixture_bridge;grant fixture_bridge to authenticated');
 await assert.rejects(()=>db.exec(sql));assertions++;
 await db.exec('rollback;revoke fixture_bridge from authenticated;revoke sko_security_collector_ingest from fixture_bridge');
 await db.exec('alter role sko_security_collector_ingest bypassrls');
 await assert.rejects(()=>db.exec(sql));assertions++;
 await db.exec('rollback;alter role sko_security_collector_ingest nobypassrls');
 await db.exec('create role fixture_danger bypassrls;grant fixture_danger to sko_security_collector_ingest');
 await assert.rejects(()=>db.exec(sql));assertions++;
 await db.exec('rollback;revoke fixture_danger from sko_security_collector_ingest');
 await db.exec(sql);
 const actor='00000000-0000-0000-0000-000000000001';
 const event={event_id:'00000000-0000-0000-0000-000000000010',collector_id:'00000000-0000-0000-0000-000000000020',
  occurred_at:new Date().toISOString(),event_kind:'current_lure_touched',generation:1,
  correlation_key:'a'.repeat(64),key_epoch:new Date().toISOString().slice(0,10)};
 const ingest='select private.ingest_security_collector_event($1::jsonb)';
 const read='select private.read_security_collector_events($1::text)';
 await role('sko_security_collector_ingest');await deny(ingest,[event]);
 await role('authenticated');await deny(read,['proof']);
 await db.exec(`reset role;update private.security_collector_control set ingest_enabled=true,read_enabled=true;
 set test.actor='${actor}';set test.allowed='true';set test.master='true';`);
 for(const apiRole of ['anon','authenticated','service_role']) {
  await role(apiRole);await deny(ingest,[event]);
  await deny('select * from private.security_collector_events');
  await deny('insert into private.security_collector_events select * from private.security_collector_events');
 }
 await role('sko_security_collector_ingest');
 checked(await scalar(ingest,[event])===event.event_id,'writer accepted valid sanitized metadata');
 checked(await scalar(ingest,[event])===event.event_id,'same event retry is idempotent');
 await deny(ingest,[{...event,generation:2}]);
 for(const extra of ['ip','email','phone','path','body','headers','authorization','source_provenance','attack_confirmed']) {
  await deny(ingest,[{...event,[extra]:'forged'}]);
 }
 for(const patch of [{generation:'1'},{generation:0},{generation:1000001},{correlation_key:'raw address'},
  {event_kind:'attack_confirmed'},{key_epoch:'2000-01-01'},{occurred_at:'infinity'},
  {occurred_at:new Date(Date.now()+3600000).toISOString()}, {occurred_at:new Date(Date.now()-3600000).toISOString()},
  {collector_id:null},{event_id:'not-uuid'},{event_kind:null}]) await deny(ingest,[{...event,...patch}]);
 await deny(read,['proof']);await deny('select * from private.security_collector_read_audit');
 await deny('update private.security_collector_events set generation=2');
 await deny('delete from private.security_collector_events');
 await db.exec(`reset role;insert into private.fixture_proofs(token,actor) values('proof','${actor}');`);
 for(const state of [{master:false,allowed:true},{master:true,allowed:false}]) {
  await db.exec(`reset role;set test.master='${state.master}';set test.allowed='${state.allowed}';`);
  await role('authenticated');await deny(read,['proof']);
 }
 await db.exec(`reset role;set test.master='true';set test.allowed='true';set test.actor='';`);
 await role('authenticated');await deny(read,['proof']);
 await db.exec(`reset role;set test.actor='${actor}';`);
 await role('authenticated');await deny(read,['wrong']);
 const result=await scalar(read,['proof']);
 checked(result.events.length===1 && result.attack_confirmed===false,'master sees an observation, not an attack assertion');
 checked(result.events[0].source_provenance==='trusted_collector_observation','distinct provenance, never synthetic');
 await deny(read,['proof']);
 await db.exec('reset role');
 checked(await scalar('select count(*)::integer from private.security_collector_events')===1,'rejections preserve only one event');
 checked(await scalar('select count(*)::integer from private.security_collector_read_audit')===1,'successful read audited once');
 checked(await scalar('select actor_id from private.security_collector_read_audit')===actor,'server actor recorded');
 checked(await scalar(`select count(*)::integer from pg_policies where tablename like 'security_collector_%'` )===0,'no API table policies');
 // An audit persistence failure rolls back the proof consumption and read.
 await db.exec(`insert into private.fixture_proofs(token,actor) values('rollback','${actor}');
 create function private.fixture_fail_audit() returns trigger language plpgsql as $$begin raise exception 'fixture audit failure';end$$;
 create trigger fixture_fail_audit before insert on private.security_collector_read_audit for each row execute function private.fixture_fail_audit();`);
 await role('authenticated');await deny(read,['rollback']);await db.exec('reset role');
 checked(await scalar("select not used from private.fixture_proofs where token='rollback'")===true,'failed audit rolls proof consumption back');
 await db.exec('drop trigger fixture_fail_audit on private.security_collector_read_audit');
 await role('authenticated');await scalar(read,['rollback']);await db.exec('reset role');
 checked(await scalar('select count(*)::integer from private.security_collector_read_audit')===2,'retry audited after recovery');
 await db.exec('update private.security_collector_control set ingest_enabled=false,read_enabled=false');
 await role('sko_security_collector_ingest');await deny(ingest,[event]);
 await role('authenticated');await deny(read,['rollback']);await db.exec('reset role');
 checked(await scalar('select not ingest_enabled and not read_enabled from private.security_collector_control')===true,'both gates returned OFF');
 console.log(JSON.stringify({pass:true,assertions,production_changed:false,transport_implemented:false,
  proof_issuer_is_fixture:true,deployment_ready:false}));
} finally {await db.close();}
