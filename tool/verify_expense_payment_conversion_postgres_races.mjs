import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';

const connectionString=process.env.SKO_EXPENSE_CONVERSION_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_expense_conversion_fixture';
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
// Reuse exact conversion fixture setup and run on native PG17, not an alternate SQL model.
const setup=fs.readFileSync('tool/verify_expense_payment_v1_draft_conversion.mjs','utf8').split(' const original=await row')[0]
 .replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
 .replace("import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';",'')
 .replace('const {PGlite}=await import(process.argv[2]);','').replace('try {','');
const foundation=await new(Object.getPrototypeOf(async function(){}).constructor)('fs','assert','PGlite','setupExpenseCostFixture',setup+';return db;')(fs,assert,Fixture,setupExpenseCostFixture);
const clients=[],id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
async function connect(name){const c=make(name);await c.connect();clients.push(c);await c.query("set statement_timeout='15s';set lock_timeout='10s'");await c.query(`set test.uid='${id(3)}'`);return c;}
const pending=p=>{p.catch(()=>{});return p;};
try{
 const a=await connect('conversion-a'),b=await connect('conversion-b'),observer=await connect('conversion-observer');
 await a.query(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${id(1)}'::uuid$$;
 create or replace function private.expense_direction_v2_client_rollout_verified(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${id(1)}'::uuid$$`);
 const row=async month=>(await observer.query('select to_jsonb(p) value from payment_certificates p where period_start=$1',[`2026-${month}-01`])).rows[0].value;
 async function args(r){return [r.company_id,r.id,r.partner_company_id,r.period_start,r.revision,JSON.stringify(r),(await observer.query('select md5($1::jsonb::text) h',[JSON.stringify(r)])).rows[0].h,'fixture-backup','fixture-rollout'];}
 const convert=(c,v)=>c.query('select private.convert_payment_expense_v1_draft($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9) value',v);
 async function waitLock(name){const end=Date.now()+8000;while(Date.now()<end){await observer.query('select pg_stat_clear_snapshot()');const r=await observer.query("select pg_blocking_pids(pid) blockers from pg_stat_activity where application_name=$1 and wait_event_type='Lock'",[name]);if(r.rows.some(x=>x.blockers.length))return;await new Promise(r=>setTimeout(r,25));}throw Error('expected actual PostgreSQL blocking lock: '+name);}
 const original=await row('07'),v=await args(original);
 await a.query('begin');await a.query('select id from payment_certificates where id=$1 for update',[original.id]);
 const first=pending(convert(b,v));await waitLock('conversion-b');
 await assert.rejects(convert(a,v),e=>e.code==='40001');await a.query('rollback');
 const after=(await first).rows[0].value;assert.equal(after.net_amount,-1000);assert.equal(after.revision,original.revision+1);
 assert.deepEqual((await convert(a,v)).rows[0].value,after);
 assert.equal((await observer.query('select count(*)::int n from private.expense_payment_direction_conversions where document_id=$1',[original.id])).rows[0].n,1);
 // Converter holds row + scope. Finalizer acquires row only after commit, sees v2.
 const aug=await row('08'),av=await args(aug);await a.query('begin');await convert(a,av);
 const finalizing=pending(b.query("update payment_certificates set status='finalized' where id=$1",[aug.id]));await waitLock('conversion-b');await a.query('commit');await finalizing;
 assert.equal((await row('08')).net_amount,-1000);
 assert.equal((await observer.query("select count(*)::int n from private.expense_amount_consumptions where document_id=$1 and purpose='cost_recovery'",[aug.id])).rows[0].n,1);
 await assert.rejects(convert(a,av),/retry differs/);
 // Finalizer first owns scope; converter refuses 40001 then finalized row on retry.
 const sep=await row('09'),sv=await args(sep);await a.query('begin');await a.query("update payment_certificates set status='finalized' where id=$1",[sep.id]);
 await assert.rejects(convert(b,sv),e=>e.code==='40001');await a.query('commit');await assert.rejects(convert(b,sv),/automatic draft/);
 assert.equal((await row('09')).net_amount,1000);
 // Fresh legacy fixture for claim-first / scope-first competing allocation.
 await observer.query(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select false$$;
 insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen) values('${id(30)}','${id(1)}','${id(2)}','検証社員','${id(3)}','2026-11-01','2026-11-01','競合経費',1000);
 select public.expense_confirm_review('${id(130)}','${id(30)}',1,'approve','subcontractor','${id(5)}','cash','');
 create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${id(1)}'::uuid$$`);
 const nov=await row('11'),nv=await args(nov);await a.query('begin');await a.query('select id from private.expense_claims where id=$1 for update',[id(30)]);
 const converting=pending(convert(b,nv));await waitLock('conversion-b');
 await assert.rejects(a.query("select public.expense_allocate_with_cost($1,$2,2,'ownCompany',null)",[id(131),id(30)]),e=>e.code==='40001');await a.query('rollback');
 assert.equal((await converting).rows[0].value.net_amount,-1000);
 assert.equal((await observer.query('select allocation from private.expense_claims where id=$1',[id(30)])).rows[0].allocation,'subcontractor');
 assert.equal((await observer.query('select count(*)::int n from private.expense_cost_allocation_events where command_id=$1',[id(131)])).rows[0].n,0);
 console.log('PASS PG17 real blocking locks: duplicate command one receipt; conversion/finalization both orders; claim-first allocation 40001 without deadlock or extra receipt/consumption.');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));await foundation.close();}
