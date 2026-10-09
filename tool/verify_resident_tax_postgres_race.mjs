// Runs after the same harness bootstraps the disposable native PG17 fixture.
import assert from 'node:assert/strict';
import {validateResidentTaxFixtureUrl} from './resident_tax_pg17_database_guard.mjs';
const connectionString=validateResidentTaxFixtureUrl(process.env.SKO_RESIDENT_TAX_FIXTURE_URL);
const module=await import(process.argv[2]);
const Client=module.Client??module.default?.Client;
const clients=[new Client({connectionString}),new Client({connectionString}),new Client({connectionString})];
const [monitor,first,second]=clients;
const company='10000000-0000-0000-0000-000000000001';
const worker='40000000-0000-0000-0000-000000000001';
const editor='00000000-0000-0000-0000-000000000002';
const readSql='select public.read_worker_resident_tax_schedule($1,$2,$3) as result';
const saveSql='select public.save_worker_resident_tax_schedule($1,$2,$3,$4,$5,$6::jsonb,true) as result';
async function payrollRows() {
  return (await monitor.query("select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]'::jsonb) as rows from public.payroll_statements p")).rows[0].rows;
}
try {
  await Promise.all(clients.map(client=>client.connect()));
  assert.equal(Math.floor(Number((await monitor.query('show server_version_num')).rows[0].server_version_num)/10000),17);
  assert.equal((await monitor.query('select public.resident_tax_schedule_contract_version() as version')).rows[0].version,1);
  for(const client of clients) {
    await client.query("set statement_timeout='10s'; set lock_timeout='5s'");
  }
  for(const client of [first,second]) {
    await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('test.account_access_denied','',false)",[editor]);
    await client.query('set role authenticated');
  }
  const dates=(await monitor.query("select date_trunc('month',now() at time zone 'Asia/Tokyo')::date::text as current,(date_trunc('month',now() at time zone 'Asia/Tokyo')+interval '1 month')::date::text as future")).rows[0];
  const before=(await first.query(readSql,[company,worker,dates.current])).rows[0].result;
  assert.equal(before.state.mode,'timeline');
  const oldPayroll=await payrollRows();
  const entries=before.state.entries.filter(entry=>entry.effective_month!==dates.future);
  const expectedVersion=before.state.version;
  await first.query('begin');
  const winner=(await first.query(saveSql,[company,worker,expectedVersion,'timeline',before.state.cutover_month,
    JSON.stringify([...entries,{effective_month:dates.future,amount_yen:18000}])])).rows[0].result;
  assert.equal(winner.version,expectedVersion+1);
  const secondPid=(await second.query('select pg_backend_pid() as pid')).rows[0].pid;
  let settled=false;
  const pending=second.query(saveSql,[company,worker,expectedVersion,'timeline',before.state.cutover_month,
    JSON.stringify([...entries,{effective_month:dates.future,amount_yen:19000}])]).then(
    result=>{settled=true;return {result};},error=>{settled=true;return {error};});
  const deadline=Date.now()+3000;
  let waiting=false;
  while(Date.now()<deadline && !settled) {
    const row=(await monitor.query("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted) as waiting",[secondPid])).rows[0];
    if(row.waiting) {waiting=true;break;}
    await new Promise(resolve=>setTimeout(resolve,20));
  }
  assert.equal(waiting,true,'Second editor must wait for the first transaction advisory lock');
  await first.query('commit');
  const loser=await pending;
  assert.ok(loser.error,'A stale editor must not silently overwrite the committed schedule');
  assert.equal(loser.error.code,'40001');
  assert.match(loser.error.message,/resident tax version conflict/);
  const after=(await second.query(readSql,[company,worker,dates.current])).rows[0].result;
  assert.equal(after.state.version,winner.version);
  assert.equal(after.state.entries.find(entry=>entry.effective_month===dates.future).amount_yen,18000);
  assert.deepEqual(after.resolved,before.resolved);
  assert.equal(after.history.length,before.history.length+1,'Only the winning edit may append an audit event');
  assert.deepEqual(await payrollRows(),oldPayroll,'Future-only concurrent edits must preserve every current/protected payroll row');
  console.log('PASS native PG17 two-session resident-tax race: actual advisory wait, stale version rejection, one winning history, no lost update, all payroll rows unchanged');
} finally {
  await Promise.allSettled(clients.map(async client=>{try {await client.query('rollback');} finally {await client.end();}}));
}
