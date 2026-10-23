// Isolated actual adapter-core boundary tests. No sockets/credentials/project access.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {connectionOptions,executeRequest,HOST} from './production_transport_core.mjs';
const secret='synthetic-only-never-log';
const install='BEGIN; DO $expense_operator_preflight$ BEGIN NULL; END $expense_operator_preflight$; COMMIT;';
const read='BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT 1; COMMIT;';
const req=(mode,sql)=>({mode,sql,sha256:createHash('sha256').update(sql).digest('hex'),password:secret});
const instances=[];
let encrypted=true,authorized=true,identity={},fault=null;
class Client {
 constructor(options){this.options=options;this.calls=[];this.connection={stream:{encrypted,authorized}};instances.push(this);}
 on(){}async connect(){this.connected=true;}
 async query(sql){this.calls.push(sql);
  if(sql.startsWith('select current_database')) return {rows:[{db:'postgres',actor:'postgres',effective:'postgres',path:'public',readonly:'on',...identity}]};
  if(sql===install||sql===read){if(fault)throw Error(secret);return [{rows:[]},{rows:[{jsonb_build_object:{read_only:'on',synthetic:true}}]}];}
  if(sql==='show transaction_read_only')return {rows:[{transaction_read_only:'on'}]};
  return {rows:[]};
 }
 async end(){this.ended=true;}
}
const config=connectionOptions(secret);
assert.equal(config.host,HOST);assert.equal(config.port,5432);assert.equal(config.user,'postgres');assert.equal(config.database,'postgres');
assert.equal(config.ssl.rejectUnauthorized,true);assert.equal(config.ssl.servername,HOST);assert.equal(config.ssl.minVersion,'TLSv1.2');
assert.ok(config.ssl.checkServerIdentity(HOST,{subjectaltname:'DNS:another-project.supabase.co'}));
assert.equal(config.ssl.checkServerIdentity('injected-host',{subjectaltname:'DNS:'+HOST}),undefined,'hostname argument cannot redirect certificate verification');
for(const bad of ['',secret+'\n',secret+'\0'])assert.throws(()=>connectionOptions(bad));
for(const bad of [{...req('install',install),host:'127.0.0.1'}, {...req('install',install),sha256:'0'.repeat(64)},req('restore',install),req('read-only',install)])
 await assert.rejects(executeRequest(bad,Client));
assert.equal(instances.length,0,'bad inputs refused before client construction');
assert.deepEqual(await executeRequest(req('install',install),Client),{acknowledged:true});
assert.deepEqual(await executeRequest(req('read-only',read),Client),{read_only:'on',synthetic:true});
assert.equal(instances.length,2);assert.notEqual(instances[0],instances[1]);
for(const client of instances){assert.equal(client.ended,true);assert.equal(client.calls.filter(x=>x===install||x===read).length,1);}
assert.equal(instances[1].calls.includes('set default_transaction_read_only=on'),true);
for(const change of [{actor:'service_role'},{effective:'authenticated'},{db:'other'},{path:'private, public'}]){
 identity=change;await assert.rejects(executeRequest(req('install',install),Client));assert.equal(instances.at(-1).calls.includes(install),false);
}
identity={};authorized=false;await assert.rejects(executeRequest(req('install',install),Client));assert.equal(instances.at(-1).calls.length,0);
authorized=true;encrypted=false;await assert.rejects(executeRequest(req('install',install),Client));assert.equal(instances.at(-1).calls.length,0);
encrypted=true;fault=true;const before=instances.length;await assert.rejects(executeRequest(req('install',install),Client));assert.equal(instances.length,before+1);assert.equal(instances.at(-1).calls.filter(x=>x===install).length,1);
assert.equal(instances.every(x=>x.ended),true);
console.log('PASS fixed direct project/role/TLS/hostname, pre-connect request refusal, fresh sessions, immutable single payload, failure without retry');
