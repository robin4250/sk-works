// Thin fixture adapter: executes the identical SQL test against disposable PG17.
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../tool/security/fixture_dependencies/package.json',import.meta.url));
const {Client}=require('pg');
export class PGlite {
 constructor(){
  const uri=new URL(process.env.PARTNER_BANK_TEST_DATABASE_URL??'');
  if(!['127.0.0.1','localhost'].includes(uri.hostname)||uri.pathname!='/partner_bank_fixture')throw Error('Disposable loopback fixture database required');
  this.client=new Client({connectionString:uri.href});this.ready=this.client.connect();
 }
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,params){await this.ready;return this.client.query(sql,params);}
 async close(){await this.ready;await this.client.end();}
}
