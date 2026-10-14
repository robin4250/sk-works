import {createRequire} from 'node:module';
const require = createRequire(new URL('../line_release_fixture_dependencies/package.json',import.meta.url));
const pg = require('pg');
export function fixtureUrl(value) {
  const url = new URL(value);
  if(!['postgres:','postgresql:'].includes(url.protocol) || url.hostname!=='127.0.0.1' ||
    url.pathname!=='/sko_line_release_fixture' || url.username!=='postgres' ||
    url.password!=='fixture-only' || url.search || url.hash ||
    !['','5432'].includes(url.port)) throw new Error('Disposable loopback LINE release fixture URL required');
  return url.href;
}
export class PGlite {
  constructor() {
    this.client = new pg.Client({connectionString:fixtureUrl(process.env.SKO_LINE_RELEASE_POSTGRES_URL)});
    this.ready = this.client.connect().then(async () => {
      const version = Number((await this.client.query("select current_setting('server_version_num') version")).rows[0].version);
      if(version<170000 || version>=180000) throw new Error('Postgres 17 fixture required');
      const n=(await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;
      if(n!==0) throw new Error('Empty disposable fixture database required');
    });
  }
  async exec(sql) { await this.ready; return this.client.query(sql); }
  async query(sql,params=[]) { await this.ready; return this.client.query(sql,params); }
  async close() { await this.ready; return this.client.end(); }
}
