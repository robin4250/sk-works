import {Client,types} from 'pg';
const raw=process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL;
if(!raw) throw Error('dedicated fixture URL required');
const uri=new URL(raw);
if(!['postgres:','postgresql:'].includes(uri.protocol)||uri.hostname!=='127.0.0.1'||
 uri.pathname!=='/sko_document_adjustment_fixture'||uri.username!=='postgres'||
 uri.password!=='fixture-only-password'||uri.search||uri.hash) throw Error('dedicated localhost document fixture only');
types.setTypeParser(20,value=>{const n=Number(value);if(!Number.isSafeInteger(n))throw Error('unsafe bigint');return n;});
let fixture;
export class PGlite {
 constructor(){
  if(fixture)throw Error('one fixture setup owner only');
  fixture=this;this.client=new Client({connectionString:raw});
  this.ready=this.client.connect().then(async()=>{
   const v=(await this.client.query('show server_version_num')).rows[0].server_version_num;
   if(Math.floor(Number(v)/10000)!==17)throw Error('PostgreSQL 17 required');
   if((await this.client.query("select to_regclass('public.companies') existing")).rows[0].existing)throw Error('empty fixture required');
  });
 }
 async query(sql,args){await this.ready;return this.client.query(sql,args);}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async close(){if(process.env.SKO_DOCUMENT_ADJUSTMENT_HOLD_FIXTURE!=='1')await this.client.end();}
}
export function fixtureDb(){if(!fixture)throw Error('fixture not initialized');return fixture;}
export async function connectFixture(){const c=new Client({connectionString:raw});await c.connect();return c;}
