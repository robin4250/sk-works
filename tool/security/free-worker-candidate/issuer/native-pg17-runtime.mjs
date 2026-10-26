import{pathToFileURL}from'node:url';import path from'node:path';
const modulePath=process.env.SKO_MANAGEMENT_ISSUER_PG_MODULE;if(!modulePath)throw Error('pinned fixture pg module required');const{Client}=await import(pathToFileURL(path.resolve(modulePath))); 
const raw=process.env.SKO_MANAGEMENT_ISSUER_FIXTURE_URL;if(!raw)throw Error('dedicated fixture URL required');const u=new URL(raw);
if(!['postgres:','postgresql:'].includes(u.protocol)||u.hostname!=='127.0.0.1'||u.pathname!=='/sko_management_issuer_fixture'||u.username!=='postgres'||u.password!=='fixture-only-password'||u.search||u.hash)throw Error('dedicated localhost management fixture only');
export class PGlite{
 constructor(){this.client=new Client({connectionString:raw});this.ready=this.client.connect().then(async()=>{const n=(await this.client.query('show server_version_num')).rows[0].server_version_num;if(Math.floor(Number(n)/10000)!==17)throw Error('PostgreSQL17 required');if((await this.client.query("select to_regnamespace('security_management_issuer_private')is not null existing")).rows[0].existing)throw Error('empty management fixture required')})}
 async exec(q){await this.ready;return this.client.query(q)}async query(q,args){await this.ready;return this.client.query(q,args)}async close(){await this.client.end()}
}

export async function connectFixture(){const c=new Client({connectionString:raw});await c.connect();return c;}
