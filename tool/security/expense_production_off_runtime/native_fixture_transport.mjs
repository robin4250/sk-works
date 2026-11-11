// CI ONLY: fixed empty disposable PG17 fixture. No production endpoint is accepted.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {validatePayrollScopeFixtureUrl} from '../../payroll_scope_pg17_database_guard.mjs';
let connectionString;
try{connectionString=validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL);}
catch{process.stderr.write('fixture_endpoint_refused\n');process.exit(2);}
const mode=process.argv[2];
if(!['install-ack','disconnect-before','disconnect-after','read-only','restore-fixture'].includes(mode)){
 process.stderr.write('fixture_mode_refused\n');process.exit(2);
}
const sql=fs.readFileSync(0,'utf8');
if(!sql||Buffer.byteLength(sql)>16777216){process.stderr.write('fixture_input_refused\n');process.exit(2);}
const pg=await import('../fixture_dependencies/node_modules/pg/lib/index.js');
const Client=pg.Client??pg.default?.Client;
const client=new Client({connectionString,application_name:'sko-expense-off-native-fixture',connectionTimeoutMillis:5000});
client.on('error',()=>{});
try{
 await client.connect();
 assert.equal(Math.floor(Number((await client.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 const identity=(await client.query('select current_database() db,session_user actor')).rows[0];
 assert.equal(identity.db,'sko_payroll_scope_fixture');assert.equal(identity.actor,'postgres');
 await client.query("set search_path=public;set statement_timeout='30s';set lock_timeout='3s'");
 if(mode==='read-only'){
  assert(sql.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'));
  await client.query('set default_transaction_read_only=on');
  const results=await client.query(sql);
  const actual=(Array.isArray(results)?results:[results]).flatMap(r=>r.rows??[]).find(r=>r.jsonb_build_object)?.jsonb_build_object;
  assert.equal(actual?.read_only,'on');
  assert.equal((await client.query('show transaction_read_only')).rows[0].transaction_read_only,'on');
  process.stdout.write(JSON.stringify(actual));
 }else if(mode==='restore-fixture'){
  assert(sql.includes('DO $expense_restore$')&&sql.trimEnd().endsWith('COMMIT;'));
  await client.query(sql);process.stdout.write('fixture_undo_acknowledged');
 }else{
  assert(sql.includes('DO $expense_operator_preflight$')&&sql.trimEnd().endsWith('COMMIT;'));
  if(mode==='disconnect-before'){
   // Fault injection only: withhold the final COMMIT, then kill this real backend.
   // This never modifies the immutable source/prepared SQL or production runner.
   const body=sql.trimEnd().slice(0,-'COMMIT;'.length);
   await client.query(body);
   const killer=new Client({connectionString,connectionTimeoutMillis:5000});
   try{await killer.connect();assert.equal((await killer.query('select pg_terminate_backend($1) terminated',[client.processID])).rows[0].terminated,true);}
   finally{await killer.end();}
   throw Error('fixture_disconnect_before');
  }
  await client.query(sql);
  if(mode==='disconnect-after'){
   // Server committed; discard the parent's acknowledgement through real socket teardown.
   client.connection.stream.destroy();
   throw Error('fixture_disconnect_after');
  }
  process.stdout.write('fixture_commit_acknowledged');
 }
}catch{
 process.stderr.write('fixture_transport_failed_or_ack_withheld\n');process.exitCode=3;
}finally{try{await client.end();}catch{}}
