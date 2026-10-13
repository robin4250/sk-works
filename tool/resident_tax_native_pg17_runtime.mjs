// Native PostgreSQL adapter for the existing isolated resident-tax harness.
// The PGlite export is only its constructor interface; all SQL executes on PG17.
import assert from 'node:assert/strict';
import {validateResidentTaxFixtureUrl} from './resident_tax_pg17_database_guard.mjs';
const connectionString=validateResidentTaxFixtureUrl(process.env.SKO_RESIDENT_TAX_FIXTURE_URL);
const module=await import(process.argv[3]);
const Client=module.Client??module.default?.Client;
assert.equal(typeof Client,'function','A native pg Client is required');
class NativePostgres17Fixture {
  constructor() {
    this.client=new Client({connectionString,application_name:'sko-resident-tax-pg17'});
    this.ready=this.prepare();
  }
  async prepare() {
    await this.client.connect();
    const version=(await this.client.query('show server_version_num')).rows[0].server_version_num;
    assert.equal(Math.floor(Number(version)/10000),17,'PostgreSQL 17 required');
    const count=(await this.client.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','resident_tax_private') and c.relkind in ('r','v','m')")).rows[0].n;
    assert.equal(count,0,'Disposable fixture must start empty');
    await this.client.query("set statement_timeout='30s'; set lock_timeout='10s'");
    console.log('Native PostgreSQL 17: empty disposable fixture and connection guard verified');
  }
  async exec(sql) {await this.ready;return this.client.query(sql);}
  async query(sql,values) {await this.ready;return this.client.query(sql,values);}
  async close() {try {await this.ready;} finally {await this.client.end();}}
}
export {NativePostgres17Fixture as PGlite};
