import fs from 'node:fs';import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const mode=process.argv[3];
if(!['flow','receipts'].includes(mode))throw Error('Unknown isolated verifier');
const path=mode==='flow'?'tool/verify_expense_review_flow.mjs':'tool/verify_expense_receipt_attachments.mjs';
const connectionString=process.env.SKO_EXPENSE_REVIEW_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');const database='sko_expense_review_flow_fixture';
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||
 !['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!==`/${database}`)throw Error('Only local disposable fixture permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
function client(){const c=new Client({connectionString});const p=c.connectionParameters;
 if(!['127.0.0.1','localhost','::1'].includes(p.host)||p.database!==database||Number(p.port)!==Number(url.port||5432))throw Error('Effective fixture differs');return c;}
class Fixture{
 constructor(){this.c=client();this.ready=(async()=>{await this.c.connect();
  assert.match((await this.c.query('show server_version')).rows[0].server_version,/^17\./);
  assert.equal((await this.c.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','storage')")).rows[0].n,0);})();}
 async exec(sql){await this.ready;return this.c.query(sql);}async query(sql,p){await this.ready;return this.c.query(sql,p);}async close(){await this.ready;await this.c.end();}
}
const source=fs.readFileSync(path,'utf8').replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
 .replace("import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';",'')
 .replace('const {PGlite}=await import(process.argv[2]);','');
await new(Object.getPrototypeOf(async function(){}).constructor)('fs','assert','PGlite','setupExpenseCostFixture',source)(fs,assert,Fixture,setupExpenseCostFixture);
if(mode==='flow'){
 const cs=[client(),client(),client()];await Promise.all(cs.map(c=>c.connect()));
 const [admin,a,b]=cs;const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 try{
  await admin.query(`set test.uid='${id(3)}';insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
   values('${id(100)}','${id(1)}','${id(2)}','本人','${id(3)}','2026-09-30','2026-09-30T15:00:00Z','競合確認',1234)`);
  for(const c of [a,b])await c.query(`set role authenticated;set test.uid='${id(3)}';set statement_timeout='20s'`);
  await admin.query('begin');await admin.query('select id from private.expense_claims where id=$1 for update',[id(100)]);
  const confirm=c=>c.query("select public.expense_confirm_review($1,$2,1,'approve','other',null,'advance','競合') value",[id(101),id(100)]);
  const first=confirm(a),second=confirm(b);first.catch(()=>{});second.catch(()=>{});
  await admin.query('commit');const receipts=await Promise.all([first,second]);assert.deepEqual(receipts[0].rows[0].value,receipts[1].rows[0].value);
  assert.equal((await admin.query('select count(*)::int n from private.expense_review_confirmations where command_id=$1',[id(101)])).rows[0].n,1);
  assert.equal((await admin.query('select revision from private.expense_claims where id=$1',[id(100)])).rows[0].revision,2);
  console.log('PASS PostgreSQL concurrent final confirmation produces one immutable receipt and one revision');
 }finally{await Promise.allSettled(cs.map(c=>c.end()));}
}
