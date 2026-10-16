import pg from '../fixture_dependencies/node_modules/pg/lib/index.js';
export class PGlite{
 constructor(){
  const connectionString=process.env.SKO_PERSONNEL_FIXTURE_URL;
  const u=new URL(connectionString);
  if(!['127.0.0.1','localhost','[::1]'].includes(u.hostname)||u.pathname!=='/sko_personnel_fixture')throw Error('Disposable loopback personnel fixture only');
  this.client=new pg.Client({connectionString});
  this.ready=this.client.connect().then(async()=>{
   const v=Number((await this.client.query("select current_setting('server_version_num') v")).rows[0].v);
   if(v<170000||v>=180000)throw Error('PostgreSQL17 required');
   const n=(await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;
   if(n!==0)throw Error('Empty synthetic fixture required');
  });
 }
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,values=[]){await this.ready;return this.client.query(sql,values);}
 async close(){await this.ready;return this.client.end();}
}
