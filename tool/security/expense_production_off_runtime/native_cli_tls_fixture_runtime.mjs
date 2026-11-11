// CI setup only. Fixed empty loopback PG17 database; never an operator endpoint.
import assert from 'node:assert/strict';
if(process.env.SKO_EXPENSE_NATIVE_TLS_FIXTURE!=='isolated-loopback-only')throw Error('fixture_refused');
const pg=await import(process.argv[3]);
const Client=pg.Client??pg.default?.Client;
class NativeTlsFixture {
 constructor(){this.client=new Client({host:'127.0.0.1',port:5432,user:'postgres',password:'fixture-only-password',database:'postgres',ssl:false});this.ready=this.prepare();}
 async prepare(){await this.client.connect();assert.equal(Math.floor(Number((await this.client.query('show server_version_num')).rows[0].server_version_num)/10000),17);const n=(await this.client.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth') and c.relkind in ('r','v','m')")).rows[0].n;assert.equal(n,0,'empty disposable fixture required');}
 async query(sql,args){await this.ready;return this.client.query(sql,args);}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async close(){try{await this.ready;}finally{await this.client.end();}}
}
export {NativeTlsFixture as PGlite};
