import assert from 'node:assert/strict';
import {validateResidentTaxFixtureUrl} from './resident_tax_pg17_database_guard.mjs';
const connectionString=validateResidentTaxFixtureUrl(process.env.SKO_RESIDENT_TAX_FIXTURE_URL);
const module=await import(process.argv[2]);const Client=module.Client??module.default.Client;
const a=new Client({connectionString}),b=new Client({connectionString}),observer=new Client({connectionString});
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
try {
 await Promise.all([a.connect(),b.connect(),observer.connect()]);
 assert.equal(Math.floor(Number((await observer.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 const original=(await observer.query('select * from payroll_tax_private.worker_conditions where company_id=$1 and worker_id=$2 order by starts_on desc limit 1',[cid,wid])).rows[0];
 const start='2026-09-01';assert.ok(original);
 const before=(await observer.query('select value from payroll_final_private.documents where company_id=$1 and worker_id=$2',[cid,wid])).rows;
 for(const c of [a,b]) {
  await c.query("set statement_timeout='10s';set lock_timeout='8s';begin");
  await c.query("select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true)");
  await c.query('set local role authenticated');
 }
 const first={...original.value,dependents:2},second={...original.value,dependents:3};
 await a.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5,true)',[cid,wid,start,original.version,first]);
 const pidA=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 const pidB=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=b.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5,true)',[cid,wid,start,original.version,second]).then(()=>({ok:true}),error=>({error}));
 let blocked=false;
 for(let i=0;i<100;i++) {
  const pids=(await observer.query('select pg_blocking_pids($1) pids',[pidB])).rows[0].pids;
  if(pids.includes(pidA)){blocked=true;break;}
  await new Promise(resolve=>setTimeout(resolve,20));
 }
 assert.equal(blocked,true,'the competing save must wait for the actual first backend');
 await a.query('commit');const outcome=await pending;
 assert.equal(outcome.error?.code,'40001');await b.query('rollback');
 const saved=(await observer.query('select version,value from payroll_tax_private.worker_conditions where company_id=$1 and worker_id=$2 and starts_on=$3',[cid,wid,start])).rows[0];
 assert.equal(Number(saved.version),Number(original.version)+1);assert.deepEqual(saved.value,first);
 assert.deepEqual((await observer.query('select value from payroll_final_private.documents where company_id=$1 and worker_id=$2',[cid,wid])).rows,before);
 console.log('PASS native PG17: competing saves serialize, stale version rejected, finalized document preserved');
} finally {
 for(const c of [a,b]) {try {await c.query('rollback');}catch {}}
 await Promise.allSettled([a.end(),b.end(),observer.end()]);
}
