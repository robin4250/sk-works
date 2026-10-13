import assert from 'node:assert/strict';
import {validateNormalPayrollFixtureUrl} from './payroll_normal_api_pg17_database_guard.mjs';
const connectionString=validateNormalPayrollFixtureUrl(process.env.SKO_PAYROLL_NORMAL_API_FIXTURE_URL);
const module=await import(process.argv[3]);
const Client=module.Client??module.default?.Client;
assert.equal(typeof Client,'function','A native pg Client is required');
class NativePostgres17Fixture{
 constructor(){this.client=new Client({connectionString,application_name:'sko-normal-payroll-pg17'});this.ready=this.prepare();}
 async prepare(){await this.client.connect();const v=(await this.client.query('show server_version_num')).rows[0].server_version_num;assert.equal(Math.floor(Number(v)/10000),17,'PostgreSQL 17 required');const n=(await this.client.query("select count(*)::integer n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where ns.nspname in ('public','private','auth','resident_tax_private','payroll_final_private','payroll_scope_private') and c.relkind in ('r','v','m')")).rows[0].n;assert.equal(n,0,'Disposable fixture must start empty');await this.client.query("set statement_timeout='30s';set lock_timeout='10s'");}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,values){await this.ready;return this.client.query(sql,values);}
 async close(){try{await this.ready;}finally{await this.client.end();}}
}
export{NativePostgres17Fixture as PGlite};
