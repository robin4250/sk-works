import pg from './fixture_dependencies/node_modules/pg/lib/index.js';
export class PGlite {
 constructor(){const u=new URL(process.env.SKO_PLATFORM_FIXTURE_URL);if(u.hostname!=='127.0.0.1'||u.pathname!=='/sko_platform_fixture')throw Error('Disposable loopback fixture only');this.client=new pg.Client({connectionString:u.href});this.ready=this.client.connect().then(async()=>{const v=(await this.client.query("select current_setting('server_version_num')::int v")).rows[0].v;if(v<170000||v>=180000)throw Error('Postgres 17 required');const n=(await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;if(n)throw Error('Empty fixture required');});}
 async exec(q){await this.ready;return this.client.query(q);}async query(q,p=[]){await this.ready;return this.client.query(q,p);}async close(){await this.client.end();}
}
