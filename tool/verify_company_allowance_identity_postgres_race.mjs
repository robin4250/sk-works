import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
// Guard is shared with the native harness and runs before opening connections.
await import('./company_allowance_identity_native_pg17_runtime.mjs');
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href);
const Client=pg.Client??pg.default.Client;
const clients=Array.from({length:3},()=>new Client({connectionString:process.env.SKO_ALLOWANCE_IDENTITY_FIXTURE_URL}));
const [monitor,first,second]=clients;
const c='10000000-0000-0000-0000-000000000002',owner='20000000-0000-0000-0000-000000000004';
const stateSql='select public.read_company_allowance_identity_admin($1) v';
const editSql="select public.save_company_allowance_identity_slot($1,1,$2,$3,'回',900,true) v";
try {
 await Promise.all(clients.map(x=>x.connect()));
 for(const client of [first,second]){
  await client.query("set statement_timeout='10s';set lock_timeout='5s'");
  await client.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
  await client.query('set role authenticated');
 }
 const before=(await first.query(stateSql,[c])).rows[0].v;
 await first.query('select public.adopt_company_allowance_identity($1,$2::jsonb,true)',[c,JSON.stringify(before.observed_slots)]);
 const adopted=(await first.query(stateSql,[c])).rows[0].v;
 await first.query('begin');
 const winner=(await first.query(editSql,[c,adopted.version,'勝者名称'])).rows[0].v;
 let settled=false;
 const pid=(await second.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=second.query(editSql,[c,adopted.version,'競合名称']).then(result=>{settled=true;return {result};},error=>{settled=true;return {error};});
 const deadline=Date.now()+3000;let waiting=false;
 while(Date.now()<deadline&&!settled){
  waiting=(await monitor.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[pid])).rows[0]?.waiting===true;
  if(waiting)break;await new Promise(resolve=>setTimeout(resolve,20));
 }
 assert.equal(waiting,true,'second real session must wait for company-to-settings mutation serialization');
 await first.query('commit');const loser=await pending;
 assert.equal(loser.error?.code,'40001');assert.match(loser.error?.message??'',/version conflict/);
 const result=(await second.query(stateSql,[c])).rows[0].v;
 assert.equal(result.version,winner.version);assert.equal(result.items[0].name,'勝者名称');
 assert.equal(result.items[0].id,adopted.items[0].id);assert.equal(result.history.length,2);
 console.log('PASS PG17 allowance race: company-to-settings serialization wait, one winning rename/UUID/history, stale writer rejected');
} catch(error){console.error(error.message);process.exitCode=1;}finally{
 await Promise.allSettled(clients.map(async x=>{try{await x.query('rollback');}finally{await x.end();}}));
}
