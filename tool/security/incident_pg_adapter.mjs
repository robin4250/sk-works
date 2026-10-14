import pg from './fixture_dependencies/node_modules/pg/lib/index.js';
export class PGlite {
 constructor(){
  const connectionString=process.env.SKO_INCIDENT_FIXTURE_URL;
  const url=new URL(connectionString);
  if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_incident_fixture')throw Error('Only disposable loopback incident fixture is supported');
  this.connectionString=connectionString;this.client=new pg.Client({connectionString});
  this.ready=this.client.connect().then(async()=>{
   const version=Number((await this.client.query("select current_setting('server_version_num') v")).rows[0].v);
   if(version<170000||version>=180000)throw Error('Postgres 17 required');
   const tables=(await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;
   if(tables!==0)throw Error('Empty fixture required');
  });
 }
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,values=[]){await this.ready;return this.client.query(sql,values);}
 async close(){await this.ready;return this.client.end();}
 async concurrent(uid,record){
  const clients=Array.from({length:6},()=>new pg.Client({connectionString:this.connectionString}));
  try{
   await Promise.all(clients.map(async c=>{await c.connect();await c.query('set role authenticated');await c.query("select set_config('test.uid',$1,false),set_config('test.master','true',false)",[uid]);}));
   await Promise.all(clients.map(c=>c.query('select public.save_master_security_incident($1::jsonb,1)',[JSON.stringify(record)])));
  }finally{await Promise.all(clients.map(c=>c.end()));}
 }
}
