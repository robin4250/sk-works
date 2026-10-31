import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
import {readFileSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const base = new URL('.', import.meta.url);
const read = readFileSync(new URL('read-catalog.sql', base), 'utf8');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema private;
create table private.worker_document_exemption_settings(singleton boolean primary key check(singleton),enabled boolean not null);
insert into private.worker_document_exemption_settings values(true,false);
create table private.worker_document_exemptions(id integer primary key);
create table private.worker_document_exemption_events(id bigint generated always as identity primary key);
create function private.require_reauthentication_session() returns uuid language sql as $$select null::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select true$$;
create function private.worker_document_exemption(text,jsonb) returns jsonb language sql as $$select '{}'::jsonb$$;
create function public.worker_document_exemption(text,jsonb) returns jsonb language sql as $$select '{}'::jsonb$$;
create function public.current_user_required_document_attention() returns jsonb language sql as $$select '{}'::jsonb$$;`);
const snapshot = async () => (await db.query(read)).rows[0].snapshot;
const baseline = await snapshot();
writeFileSync(new URL('synthetic-snapshot.fixture.json', base), JSON.stringify(baseline));
function capsule(target, approved=true, snapshot=baseline) {
  const script = `import json,sys\nfrom prepare_activation import build\ns=json.loads(sys.stdin.read())\nprint(build(s,${target?'True':'False'},${approved?'True':'False'}))`;
  const r=spawnSync('python3',['-c',script],{cwd:base, input:JSON.stringify(snapshot),encoding:'utf8'});
  if(r.status!==0)throw new Error(r.stderr);
  return r.stdout;
}
let checks=0;
async function denied(sql,label){

  await assert.rejects(()=>db.exec(sql),label); await db.exec('rollback');checks++;
}
await denied(capsule(true,false),'approval absent');
assert.equal((await snapshot()).module_state.enabled,false);checks++;
await db.exec(capsule(true));assert.equal((await snapshot()).module_state.enabled,true);checks++;
await denied(capsule(true),'repeat activation');
const onSnapshot=structuredClone(baseline);onSnapshot.module_state.enabled=true;
await db.exec(capsule(false,true,onSnapshot));assert.equal((await snapshot()).module_state.enabled,false);checks++;
for(const [label,mutation,undo] of [
 ['function drift',`create or replace function private.account_access_allowed() returns boolean language sql as $$select false$$`,`create or replace function private.account_access_allowed() returns boolean language sql as $$select true$$`],
 ['unknown ACL',`grant select on private.worker_document_exemptions to authenticated`,`revoke select on private.worker_document_exemptions from authenticated`],
 ['decision exists',`insert into private.worker_document_exemptions values(1)`,`delete from private.worker_document_exemptions`],
 ['event exists',`insert into private.worker_document_exemption_events default values`,`delete from private.worker_document_exemption_events`],
 ['column default drift',`alter table private.worker_document_exemption_settings alter column enabled set default true`,`alter table private.worker_document_exemption_settings alter column enabled drop default`],
 ['index drift',`create index added_exemption_index on private.worker_document_exemptions(id)`,`drop index private.added_exemption_index`],
 ['reloptions drift',`alter table private.worker_document_exemption_settings set (autovacuum_enabled=false)`,`alter table private.worker_document_exemption_settings reset (autovacuum_enabled)`],
 ['sequence parameter drift',`alter sequence private.worker_document_exemption_events_id_seq increment by 2`,`alter sequence private.worker_document_exemption_events_id_seq increment by 1`],
 ['default ACL drift',`alter default privileges in schema public grant select on tables to anon`,`alter default privileges in schema public revoke select on tables from anon`],
]){
 const expected=await snapshot();
 await db.exec(mutation);await denied(capsule(true,true,expected),label);
 assert.equal((await snapshot()).module_state.enabled,false);checks++;
 await db.exec(undo);
}
// Rebuild synthetic baseline after fixture ACL add/revoke (NULL vs explicit owner ACL).
const fresh=await snapshot();
await db.exec(`create function private.synthetic_trigger() returns trigger language plpgsql as $$begin return new;end$$;
create trigger unexpected_before_setting before update on private.worker_document_exemption_settings for each row execute function private.synthetic_trigger();`);
await denied(capsule(true,true,fresh),'unknown trigger');
assert.equal((await snapshot()).module_state.enabled,false);checks++;
await db.close();
const receipt={checks,success:true,scope:'guard/CAS/approval/rollback only; synthetic helper bodies, no auth/business/production execution',production_applied:false};
writeFileSync(new URL('synthetic-guard-test-receipt.private.json',base),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt));
