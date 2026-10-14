import pg from './security/fixture_dependencies/node_modules/pg/lib/index.js';
export class PGlite{
 constructor(){
  const raw=process.env.SKO_TRADE_FIXTURE_URL;const url=new URL(raw);
  if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_trade_fixture'||url.username!=='postgres'||url.password!=='fixture-only'||url.search||url.hash)throw Error('Only the disposable loopback trade fixture is supported');
  this.connectionString=raw;this.client=new pg.Client({connectionString:raw});
  this.ready=this.client.connect().then(async()=>{
   const version=Number((await this.client.query("select current_setting('server_version_num') v")).rows[0].v);
   if(version<170000||version>=180000)throw Error('PostgreSQL 17 required');
   if((await this.client.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n!==0)throw Error('Empty disposable fixture required');
  });
 }
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,values=[]){await this.ready;return this.client.query(sql,values);}
 async concurrentSave(actor,args){
  const clients=Array.from({length:4},()=>new pg.Client({connectionString:this.connectionString}));
  try{
   await Promise.all(clients.map(async client=>{await client.connect();await client.query('set role authenticated');await client.query("select set_config('test.uid',$1,false)",[actor]);}));
   return await Promise.allSettled(clients.map(client=>client.query('select public.save_trade_document_attachment($1,$2,$3,$4,$5) result',args)));
  }finally{await Promise.all(clients.map(client=>client.end()));}
 }
 async close(){await this.ready;return this.client.end();}
}
