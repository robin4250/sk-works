import assert from 'node:assert/strict';import{validateRateViewerFixtureUrl}from'./company_rate_viewer_pg17_database_guard.mjs';
const connectionString=validateRateViewerFixtureUrl(process.env.SKO_COMPANY_RATE_VIEWER_FIXTURE_URL);const module=await import(process.argv[3]);const Client=module.Client??module.default?.Client;
assert.equal(typeof Client,'function','Native pg Client required');
class NativeFixture{
 constructor(){this.client=new Client({connectionString,application_name:'sko-rate-viewer-pg17'});this.ready=this.prepare();}
 async prepare(){await this.client.connect();assert.equal(Math.floor(Number((await this.client.query('show server_version_num')).rows[0].server_version_num)/10000),17);assert.equal((await this.client.query("select count(*)::int as n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','auth','private','payroll_rate_private') and c.relkind in ('r','v','m')")).rows[0].n,0,'Fixture must start empty');await this.client.query("set statement_timeout='30s';set lock_timeout='10s'");}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async query(sql,values){await this.ready;return this.client.query(sql,values);}
 async close(){try{await this.ready;}finally{await this.client.end();}}
}
export{NativeFixture as PGlite};
