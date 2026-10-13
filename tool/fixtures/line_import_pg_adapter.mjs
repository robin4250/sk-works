import pg from 'pg';
export class PGlite {
  constructor() {
    const value = process.env.SKO_LINE_IMPORT_POSTGRES_URL;
    const url = new URL(value);
    if (!['127.0.0.1','localhost','[::1]'].includes(url.hostname) || url.pathname !== '/sko_line_import_fixture') throw new Error('Use only the disposable loopback LINE fixture database');
    this.client = new pg.Client({connectionString:value});
    this.ready = this.client.connect().then(async () => {
      const version = Number((await this.client.query("select current_setting('server_version_num') version")).rows[0].version);
      if (version < 170000 || version >= 180000) throw new Error('Postgres 17 fixture required');
      const tables = (await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;
      if (tables !== 0) throw new Error('Only an empty disposable fixture database is supported');
    });
  }
  async exec(sql) { await this.ready; return this.client.query(sql); }
  async query(sql,params=[]) { await this.ready; return this.client.query(sql,params); }
  async close() { await this.ready; return this.client.end(); }
}
