import fs from 'node:fs';
import assert from 'node:assert/strict';
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const connectionString=process.env.SKO_EXPENSE_SETTLEMENT_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_expense_settlement_race_fixture';
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!==`/${database}`)throw Error('Only a local disposable expense fixture is permitted');
function make(name){const c=new Client({connectionString,application_name:name});const p=c.connectionParameters;
 if(!['127.0.0.1','localhost','::1'].includes(p.host)||p.database!==database||Number(p.port)!==Number(url.port||5432))throw Error('Effective connection must remain in the disposable fixture');return c;}
class Fixture{
 constructor(){this.client=make('expense-fixture');this.ready=(async()=>{await this.client.connect();
  assert.match((await this.client.query('show server_version')).rows[0].server_version,/^17\./);
  assert.equal((await this.client.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0,'never replace existing schemas');})();}
 async exec(s){await this.ready;return this.client.query(s);}
 async query(s,p){await this.ready;return this.client.query(s,p);}
 async close(){await this.ready;await this.client.end();}
}
const verifier=fs.readFileSync('tool/verify_expense_settlement_choices.mjs','utf8')
 .replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
 .replace('const {PGlite}=await import(process.argv[2]);','');
await new(Object.getPrototypeOf(async function(){}).constructor)('fs','assert','PGlite',verifier)(fs,assert,Fixture);
const clients=[];
async function connect(name){const c=make(name);await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const settle=p=>{p.catch(()=>{});return p;};
try{
 const admin=await connect('expense-admin'),a=await connect('expense-choice-a'),b=await connect('expense-choice-b'),observer=await connect('expense-observer');
 for(const c of [a,b])await c.query(`set role authenticated;set test.actor='${id(2)}';set test.blocked='false'`);
 async function blocked(){const deadline=Date.now()+8000;while(Date.now()<deadline){
  await observer.query('select pg_stat_clear_snapshot()');
  const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name in ('expense-choice-a','expense-choice-b') and wait_event_type='Lock'");
  if(r.rows[0].n===2)return;await new Promise(resolve=>setTimeout(resolve,25));}throw Error('Two blocked expense connections were not observed');}
 const approve=(c,n,version)=>c.query("select public.expense_approve_with_settlement($1,$2,$3,'payroll','2026-11-01') v",[id(n),id(10),version]);
 await admin.query('begin');await admin.query('select id from private.expense_claims where id=$1 for update',[id(10)]);
 const p=settle(approve(a,104,10)),q=settle(approve(b,104,10));await blocked();await admin.query('commit');
 const receipts=await Promise.all([p,q]);assert.deepEqual(receipts[0].rows[0].v,receipts[1].rows[0].v);
 assert.equal((await admin.query('select count(*)::int n from private.expense_settlement_events where command_id=$1',[id(104)])).rows[0].n,1);
 await admin.query("update workers set status='active' where id=$1",[id(3)]);
 await admin.query('begin');await admin.query('select id from private.expense_claims where id=$1 for update',[id(10)]);
 const edit=settle(b.query("select public.expense_personal_change($1,$2,10,'edit','2026-09-29','改訂経費',2234) v",[id(105),id(10)]));
 const old=settle(approve(a,106,10));await blocked();await admin.query('commit');
 const outcomes=await Promise.allSettled([edit,old]);assert.equal(outcomes[0].status,'fulfilled');
 if(outcomes[1].status==='rejected')assert.equal(outcomes[1].reason.code,'40001');
 const current=(await admin.query('select approval,revision,amount_yen from private.expense_claims where id=$1',[id(10)])).rows[0];
 assert.deepEqual(current,{approval:'pending',revision:11,amount_yen:2234});
 assert.equal((await admin.query('select count(*)::int n from private.expense_settlement_choices where claim_id=$1',[id(10)])).rows[0].n,1);
 console.log('PASS PostgreSQL 17 actual dual-connection fixed approval and edit/old-approval races; one choice and one fixed receipt, latest expense remains pending');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
