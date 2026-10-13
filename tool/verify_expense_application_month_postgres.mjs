import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const connectionString=process.env.SKO_EXPENSE_APPLICATION_MONTH_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_expense_application_month_fixture';
if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.search || url.hash ||
    !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.pathname!==`/${database}`) {
  throw Error('Only a local disposable application-month fixture is permitted');
}
const pg=await import(process.argv[2]);
const Client=pg.Client??pg.default?.Client;
class Fixture {
  constructor() {
    this.client=new Client({connectionString});
    const effective=this.client.connectionParameters;
    if (!['127.0.0.1','localhost','::1'].includes(effective.host) || effective.database!==database ||
        Number(effective.port)!==Number(url.port||5432)) throw Error('Effective fixture connection differs');
    this.ready=(async()=>{
      await this.client.connect();
      assert.match((await this.client.query('show server_version')).rows[0].server_version,/^17\./);
      assert.equal((await this.client.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0);
    })();
  }
  async exec(sql) { await this.ready; return this.client.query(sql); }
  async query(sql,params) { await this.ready; return this.client.query(sql,params); }
  async close() { await this.ready; await this.client.end(); }
}
const source=fs.readFileSync('tool/verify_expense_application_month.mjs','utf8')
  .replace("import fs from 'node:fs';",'').replace("import assert from 'node:assert/strict';",'')
  .replace("import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';",'')
  .replace('const {PGlite} = await import(process.argv[2]);','');
await new(Object.getPrototypeOf(async function(){}).constructor)(
  'fs','assert','PGlite','setupExpenseCostFixture',source)(fs,assert,Fixture,setupExpenseCostFixture);
