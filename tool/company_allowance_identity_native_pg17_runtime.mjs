// A disposable fixture database only. Never accepts linked/production endpoints.
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const raw=process.env.SKO_ALLOWANCE_IDENTITY_FIXTURE_URL;
if(!raw)throw new Error('Missing disposable allowance fixture URL');
const uri=new URL(raw);
if(!['postgres:','postgresql:'].includes(uri.protocol)||!['127.0.0.1','localhost'].includes(uri.hostname)||
 uri.pathname!='/sko_allowance_identity_fixture'||uri.username!=='postgres'||uri.password!=='fixture-only-password'||uri.search||uri.hash) {
 throw new Error('Only the dedicated localhost allowance fixture is permitted');
}
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href);
const Client=pg.Client??pg.default.Client;
const types=pg.types??pg.default.types;
types.setTypeParser(20,value=>{const n=Number(value);if(!Number.isSafeInteger(n))throw new Error('unsafe fixture bigint');return n;});
export class PGlite {
 constructor(){this.client=new Client({connectionString:raw});this.ready=this.client.connect().then(async()=>{
  const result=await this.client.query('show server_version_num');
  if(Math.floor(Number(result.rows[0].server_version_num)/10000)!==17)throw new Error('PostgreSQL 17 required');
  const state=await this.client.query("select to_regclass('public.company_rate_settings') as table_name");
  if(state.rows[0].table_name)throw new Error('Only an empty disposable database is permitted');
 });}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,params){await this.ready;return this.client.query(sql,params);}
 async close(){await this.client.end();}
}
