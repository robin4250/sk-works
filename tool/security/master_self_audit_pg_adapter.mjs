import pg from './master_self_audit_fixture_dependencies/node_modules/pg/lib/index.js';

// Only disposable local fixtures are accepted. Never connect this test to live data.
export class PGlite {
  constructor() {
    const url = new URL(process.env.SKO_MASTER_SELF_AUDIT_FIXTURE_URL ?? '');
    if (
      url.protocol !== 'postgres:' ||
      url.hostname !== '127.0.0.1' ||
      url.pathname !== '/sko_master_self_audit_fixture' ||
      url.username !== 'postgres' ||
      url.password !== 'fixture-only' ||
      url.search ||
      url.hash
    ) {
      throw new Error('Only the disposable loopback master audit fixture is allowed');
    }
    this.client = new pg.Client({connectionString: url.href});
    this.ready = this.client.connect();
  }

  async exec(sql) {
    await this.ready;
    return this.client.query(sql);
  }

  async query(sql, params) {
    await this.ready;
    return this.client.query(sql, params);
  }

  async close() {
    await this.ready;
    await this.client.end();
  }
}
