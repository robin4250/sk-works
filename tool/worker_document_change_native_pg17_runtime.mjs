import assert from 'node:assert/strict';
import {validateWorkerDocumentFixtureUrl} from './worker_document_change_pg17_guard.mjs';
const connectionString=validateWorkerDocumentFixtureUrl(process.env.SKO_DOCUMENT_CHANGE_FIXTURE_URL);
const pg=(await import(process.env.SKO_DOCUMENT_PG_MODULE??'/missing-approved-pg-module')).default;
// Keep database timestamp precision for compare-and-swap payloads.
for(const oid of [1082,1114,1184])pg.types.setTypeParser(oid,value=>value);
export class PGlite {
 constructor(){this.client=new pg.Client({connectionString,application_name:'sko-document-change-boundaries'});this.ready=this.prepare();}
 async prepare(){
  await this.client.connect();
  assert.equal(Math.floor(Number((await this.client.query('show server_version_num')).rows[0].server_version_num)/10000),17,'PostgreSQL17 required');
  assert.equal(Number((await this.client.query("select count(*) n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where ns.nspname not in ('pg_catalog','information_schema') and ns.nspname not like 'pg_toast%' and c.relkind in ('r','v','m')")).rows[0].n),0,'Disposable database must start empty');
  await this.client.query("set statement_timeout='20s';set lock_timeout='10s'");
 }
 async query(...args){await this.ready;return this.client.query(...args);}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async close(){try{await this.ready;}finally{await this.client.end();}}
}
