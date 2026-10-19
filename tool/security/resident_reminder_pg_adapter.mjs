import pg from './fixture_dependencies/node_modules/pg/lib/index.js';
import {resident_reminderFixtureUrl} from './resident_reminder_fixture_guard.mjs';
export class PGlite {
  constructor() {
    const connectionString = resident_reminderFixtureUrl(process.env.SKO_RESIDENT_REMINDER_FIXTURE_URL);
    this.client = new pg.Client({connectionString});
    this.ready = this.client.connect().then(async () => {
      const version = Number((await this.client.query("select current_setting('server_version_num') v")).rows[0].v);
      if (version < 170000 || version >= 180000) throw Error('PostgreSQL 17 required');
      const catalog = (await this.client.query(`
        select
          (select count(*)::int from pg_namespace where nspname !~ '^pg_' and nspname not in ('information_schema','public')) schemas,
          (select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema') relations,
          (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema') routines
      `)).rows[0];
      if (Object.values(catalog).some(count => count !== 0))
        throw Error('Empty disposable resident_reminder fixture required');
    });
  }
  async exec(sql) { await this.ready; return this.client.query(sql); }
  async query(sql, values = []) { await this.ready; return this.client.query(sql, values); }
  async close() { try { await this.ready; } finally { await this.client.end(); } }
}

