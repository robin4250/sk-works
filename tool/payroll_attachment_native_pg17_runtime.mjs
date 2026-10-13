import {Client,types} from 'pg';
const raw=process.env.SKO_PAYROLL_ATTACHMENT_FIXTURE_URL;
const uri=new URL(raw);
if(!['postgres:','postgresql:'].includes(uri.protocol)||uri.hostname!=='127.0.0.1'||uri.pathname!=='/sko_payroll_attachment_fixture'||uri.username!=='postgres'||uri.password!=='fixture-only-password'||uri.search||uri.hash)throw new Error('dedicated localhost attachment fixture only');
types.setTypeParser(20,value=>{const n=Number(value);if(!Number.isSafeInteger(n))throw new Error('unsafe bigint');return n;});
export class PGlite {
 constructor(){this.client=new Client({connectionString:raw});this.ready=this.client.connect().then(async()=>{
  const version=(await this.client.query('show server_version_num')).rows[0].server_version_num;
  if(Math.floor(Number(version)/10000)!==17)throw new Error('PostgreSQL 17 required');
  if((await this.client.query("select to_regclass('public.companies') as existing")).rows[0].existing)throw new Error('empty fixture required');
 });}
 async query(sql,args){await this.ready;return this.client.query(sql,args);}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async close(){await this.client.end();}
}
