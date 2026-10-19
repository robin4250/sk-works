import pg from './fixture_dependencies/node_modules/pg/lib/index.js';
import {collectorFixtureUrl} from './collector_fixture_guard.mjs';
export class PGlite {
  constructor() {
    const connectionString = collectorFixtureUrl(process.env.SKO_COLLECTOR_FIXTURE_URL);
    this.client = new pg.Client({connectionString});
    this.ready = this.client.connect().then(async () => {
      const version = Number((await this.client.query("select current_setting('server_version_num') v")).rows[0].v);
      if (version < 170000 || version >= 180000) throw Error('PostgreSQL 17 required');
      const count = (await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;
      if (count !== 0) throw Error('Empty disposable collector fixture required');
    });
  }
  async exec(sql) { await this.ready; return this.client.query(sql); }
  async query(sql, values = []) { await this.ready; return this.client.query(sql, values); }
  async close() { try { await this.ready; } finally { await this.client.end(); } }
}
