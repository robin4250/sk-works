// Disposable PostgreSQL fixture only. A toy writer calls the real candidate gate.
// This proves lock ordering for participating transactions, not all QR coverage.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
const here=dirname(fileURLToPath(import.meta.url));
if(process.env.CI!=='true'||process.env.PGHOST!=='127.0.0.1') throw Error('Disposable loopback CI only');
const pg=(await import(resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
const database='qr_concurrency_'+randomBytes(8).toString('hex');
const expand=p=>readFileSync(p,'utf8').split('\n').filter(l=>!l.startsWith('\\set')).map(l=>l.startsWith('\\ir ')?expand(resolve(dirname(p),l.slice(4))):l).join('\n');
const session="select set_config('fixture.actor','00000000-0000-0000-0000-000000000001',false);select set_config('fixture.session','live',false);select set_config('fixture.master','yes',false);set statement_timeout='5s';set lock_timeout='4s';";
const admin=new pg.Client(),clients=[];let created=false;
const connect=async()=>{const c=new pg.Client({database});clients.push(c);await c.connect();await c.query(session);return c;};
const waitForBlock=async(observer,pid)=>{const until=Date.now()+2000;while(Date.now()<until){const r=await observer.query('select wait_event_type from pg_stat_activity where pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,10));}throw Error('expected bounded lock wait');};
try{
 await admin.connect();await admin.query(`create database ${database}`);created=true;
 const setup=await connect(),writer=await connect(),off=await connect();
 await setup.query(expand(resolve(here,'qr-common-public-contract-test.sql')));
 await setup.query(session+"create table private.qr_writer_fixture(id int primary key);update qr_attendance_private.public_contract_rollout set enabled=true;update private.master_feature_settings set enabled=true where feature_key='qr_attendance';update private.proof_fixture set used=false;");
 const pid=(await off.query('select pg_backend_pid() pid')).rows[0].pid;
 await writer.query('begin');await writer.query('select qr_attendance_private.require_enabled()');
 await writer.query('insert into private.qr_writer_fixture values(1)');
 let finished=false;
 const disable=off.query("select public.set_master_feature_enabled_with_proof('qr_attendance',false,'fixture-off-proof')").then(x=>{finished=true;return x;});
 await waitForBlock(setup,pid);assert.equal(finished,false);
 await writer.query('commit');await disable;
 assert.equal((await setup.query("select enabled from private.master_feature_settings where feature_key='qr_attendance'")).rows[0].enabled,false);
 await writer.query('begin');
 await assert.rejects(writer.query('select qr_attendance_private.require_enabled()'),e=>e.code==='42501');
 await assert.rejects(writer.query('insert into private.qr_writer_fixture values(2)'),e=>e.code==='25P02');
 await writer.query('rollback');assert.deepEqual((await setup.query('select id from private.qr_writer_fixture order by id')).rows,[{id:1}]);
 assert.equal((await setup.query("select count(*)::int n from private.master_admin_audit_log where details->>'feature_key'='qr_attendance' and details->>'enabled'='false'")).rows[0].n,2);
 // The independent rollout OFF also waits for already-participating actions.
 await setup.query("update private.master_feature_settings set enabled=true where feature_key='qr_attendance'");
 await writer.query('begin');await writer.query('select qr_attendance_private.require_enabled()');
 const stop=off.query('update qr_attendance_private.public_contract_rollout set enabled=false');
 await waitForBlock(setup,pid);await writer.query('commit');await stop;
 await assert.rejects(writer.query('select qr_attendance_private.require_enabled()'),e=>e.code==='42501');
 console.log('QR common gate: in-flight action completes before OFF; later writes reject; rollout OFF serializes');
}finally{
 for(const c of clients){try{await c.query('rollback');}catch{}await c.end().catch(()=>{});}
 if(created)await admin.query(`drop database ${database}`).catch(()=>{});await admin.end().catch(()=>{});
}
