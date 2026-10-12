import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';

const connectionString=process.env.SKO_EXPENSE_COST_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_expense_cost_race_fixture';
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||
 !['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!==`/${database}`)
 throw Error('Only a local disposable expense cost fixture is permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
function make(name){
 const client=new Client({connectionString,application_name:name});
 const p=client.connectionParameters;
 if(!['127.0.0.1','localhost','::1'].includes(p.host)||p.database!==database||
  Number(p.port)!==Number(url.port||5432))throw Error('Effective connection must remain in the disposable fixture');
 return client;
}
class Fixture{
 constructor(){this.client=make('expense-cost-foundation');this.ready=(async()=>{
  await this.client.connect();
  assert.match((await this.client.query('show server_version')).rows[0].server_version,/^17\./);
  assert.equal((await this.client.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0,'never replace existing schemas');
 })();}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,params){await this.ready;return this.client.query(sql,params);}
 async close(){await this.ready;await this.client.end();}
}
// Repeat the amount/detail regression suite on actual PostgreSQL before races.
const verifier=fs.readFileSync('tool/verify_expense_cost_amounts.mjs','utf8')
 .replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
 .replace("import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';",'')
 .replace('const {PGlite} = await import(process.argv[2]);','');
await new(Object.getPrototypeOf(async function(){}).constructor)('fs','assert','PGlite','setupExpenseCostFixture',verifier)(fs,assert,Fixture,setupExpenseCostFixture);

const clients=[];
async function connect(name){const c=make(name);await c.connect();clients.push(c);
 await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const pending=p=>{p.catch(()=>{});return p;};
try{
 const admin=await connect('expense-cost-admin'),a=await connect('expense-cost-a'),
  b=await connect('expense-cost-b'),observer=await connect('expense-cost-observer'),
  finalizer=await connect('expense-cost-finalizer');
 for(const c of [admin,finalizer])await c.query(`set test.uid='${id(3)}'`);
 for(const c of [a,b])await c.query(`set role authenticated;set test.uid='${id(3)}'`);
 await admin.query(`insert into customers values('${id(100)}','${id(1)}','競合検証取引先','');
  insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
   values('${id(101)}','${id(1)}','${id(2)}','本人','${id(3)}','2026-11-01','競合検証経費',1234,'approved','customer','${id(100)}',2);
  insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current)
   values('${id(101)}','${id(1)}','cash','2026-11-01',2,'${id(3)}',true);`);
 async function waitForLocks(count,names=['expense-cost-a','expense-cost-b']){const deadline=Date.now()+8000;while(Date.now()<deadline){
  await observer.query('select pg_stat_clear_snapshot()');
  const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=any($1::text[]) and wait_event_type='Lock'",[names]);
  if(r.rows[0].n===count)return;await new Promise(resolve=>setTimeout(resolve,25));
 }throw Error(`Expected ${count} blocked expense cost connections`);}
 const allocate=(c,command,revision,category='customer',party=id(100))=>c.query(
  'select public.expense_allocate_with_cost($1,$2,$3,$4,$5) value',[id(command),id(101),revision,category,party]);
 await admin.query('begin');await admin.query('select id from private.expense_claims where id=$1 for update',[id(101)]);
 const first=pending(allocate(a,110,2)),second=pending(allocate(b,110,2));
 await waitForLocks(2);await admin.query('commit');
 const receipts=await Promise.all([first,second]);assert.deepEqual(receipts[0].rows[0].value,receipts[1].rows[0].value);
 assert.equal((await admin.query('select count(*)::int n from private.expense_cost_allocation_events where command_id=$1',[id(110)])).rows[0].n,1);
 const invoice=(await admin.query('select * from invoices where customer_id=$1',[id(100)])).rows[0];
 assert.equal(invoice.grand_total,1234);assert.equal(invoice.snapshot.expense_extra_claims.length,1);
 // The finalizer holds its document/scope and the charged claim. Allocation
 // waits on the claim, then must reject once the frozen document is committed.
 await admin.query('begin');await admin.query("update invoices set status='finalized' where id=$1",[invoice.id]);
 const frozen=(await admin.query('select * from invoices where id=$1',[invoice.id])).rows[0];
 const moving=pending(allocate(a,111,receipts[0].rows[0].value.revision,'ownCompany',null));
 await waitForLocks(1);await admin.query('commit');
 await assert.rejects(moving,error=>error.code==='22023');
 assert.equal(frozen.grand_total,1234);
 assert.deepEqual((await admin.query('select * from invoices where id=$1',[invoice.id])).rows[0],frozen);
 assert.equal((await admin.query("select count(*)::int n from private.expense_amount_consumptions where claim_id=$1 and purpose='cost_recovery'",[id(101)])).rows[0].n,1);
 assert.equal((await admin.query('select allocation from private.expense_claims where id=$1',[id(101)])).rows[0].allocation,'customer');
 const replay=await allocate(b,110,2);assert.deepEqual(replay.rows[0].value,receipts[0].rows[0].value);
 assert.deepEqual((await admin.query('select * from invoices where id=$1',[invoice.id])).rows[0],frozen);
 // Reverse order: a claim lock precedes a finalizer's document/scope lock.
 // The allocator must fail without waiting on that document, preventing a
 // claim -> document -> claim deadlock and leaving the finalizer's original sum.
 await admin.query(`insert into customers values('${id(120)}','${id(1)}','逆順競合検証','');
  insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision)
   values('${id(121)}','${id(1)}','${id(2)}','本人','${id(3)}','2026-11-01','逆順競合経費',1234,'approved','customer','${id(120)}',2);
  insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current)
   values('${id(121)}','${id(1)}','cash','2026-11-01',2,'${id(3)}',true,true);`);
 const reversed=(await admin.query('select * from invoices where customer_id=$1',[id(120)])).rows[0];
 await admin.query('begin');await admin.query('select id from private.expense_claims where id=$1 for update',[id(121)]);
 const finishing=pending(finalizer.query("update invoices set status='finalized' where id=$1",[reversed.id]));
 await waitForLocks(1,['expense-cost-finalizer']);
 await assert.rejects(admin.query("select public.expense_allocate_with_cost($1,$2,2,'ownCompany',null)",[id(122),id(121)]),error=>error.code==='40001');
 await admin.query('rollback');await finishing;
 assert.equal((await admin.query('select grand_total,status from invoices where id=$1',[reversed.id])).rows[0].grand_total,1234);
 assert.equal((await admin.query('select count(*)::int n from private.expense_cost_allocation_events where command_id=$1',[id(122)])).rows[0].n,0);
 assert.equal((await admin.query("select count(*)::int n from private.expense_amount_consumptions where claim_id=$1 and purpose='cost_recovery'",[id(121)])).rows[0].n,1);
 console.log('PASS PostgreSQL 17 dual-connection allocation retries and allocation/finalization race: one receipt, one consumption, original frozen amount and snapshot');
 console.log('PASS reverse-order finalizer/claim lock rejects allocation with retryable 40001, without deadlock or extra receipt');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
