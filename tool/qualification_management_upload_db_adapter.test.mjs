import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createQualificationUploadDbAdapter } from './qualification_management_upload_db_adapter.mjs';
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const args = { actorId:id(1), sessionId:id(2), requestId:id(3), slotId:id(4) };
const proof = () => ({contract:'qualification_management_upload_v1',companyId:id(5),workerId:id(6),qualificationMasterId:id(7),targetId:id(8),...args,bucket:'qualification-certificates',path:'trusted/path.png',objectId:id(9),objectVersion:'version-1',mime:'image/png',bytes:12,sha256:'a'.repeat(64)});
function fixture({result={rowCount:1,rows:[{value:{state:'prepared'}}]},fail,rollbackFails=false,connectFails=false}={}) {
 const calls=[],releases=[];
 const pool={async connect(){if(connectFails)throw Error('secret-dsn');return{async query(sql,values){calls.push({sql,values});if(sql==='ROLLBACK'&&rollbackFails)throw Error('rollback');if(fail&&fail(sql))throw Error('secret-dsn');return sql.startsWith('SELECT')?result:{rowCount:0,rows:[]};},release(error){releases.push(error);}};}};
 return {calls,releases,adapter:createQualificationUploadDbAdapter({pool})};
}
test('slot lookup uses fixed qualified SQL, detached bound IDs and transaction limits',async()=>{
 const f=fixture();assert.deepEqual(await f.adapter.authorizedPendingSlot(args),{state:'prepared'});
 assert.deepEqual(f.calls.map(x=>x.sql),['BEGIN',"SET LOCAL statement_timeout = '5s'","SET LOCAL lock_timeout = '3s'",'SELECT qualification_upload_candidate.inspection_slot($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS value','COMMIT']);
 assert.deepEqual(f.calls[3].values,[args.requestId,args.slotId,args.actorId,args.sessionId]);assert.deepEqual(f.releases,[undefined]);
});
test('invalid IDs and malformed proof never acquire a connection',async()=>{
 const f=fixture();await assert.rejects(f.adapter.authorizedPendingSlot({...args,slotId:"';select secret;"}),/inspection_unavailable/);
 for(const p of [{...proof(),bearerToken:'secret'},{...proof(),bytes:NaN},{...proof(),mime:'text/html'},{...proof(),sha256:'X'.repeat(64)}])await assert.rejects(f.adapter.commitReceiptAtomically({proof:p,expectedState:'prepared'}),/inspection_unavailable/);
 assert.equal(f.calls.length,0);
});
test('receipt uses only allowlisted JSON values copied before connection wait',async()=>{
 const f=fixture({result:{rowCount:1,rows:[{value:true}]}}),p=proof();const writing=f.adapter.commitReceiptAtomically({proof:p,expectedState:'prepared'});p.path='changed';
 assert.equal(await writing,true);const call=f.calls.find(x=>x.sql.startsWith('SELECT'));
 assert.match(call.sql,/record_receipt\(\$1::uuid,\$2::uuid,\$3::uuid,\$4::jsonb\)/);assert.equal(JSON.parse(call.values[3]).path,'trusted/path.png');assert.equal(f.releases.length,1);
});
test('database rejection rolls back and releases; secrets are not returned',async()=>{
 const f=fixture({fail:sql=>sql.startsWith('SELECT')});await assert.rejects(f.adapter.authorizedPendingSlot(args),e=>e.message==='inspection_unavailable');
 assert.equal(f.calls.at(-1).sql,'ROLLBACK');assert.equal(f.releases.length,1);assert.equal(f.releases[0],undefined);
});
test('rollback failure discards connection and begin failure never returns it healthy',async()=>{
 for(const config of [{fail:sql=>sql.startsWith('SELECT'),rollbackFails:true},{fail:sql=>sql==='BEGIN'}]){
 const f=fixture(config);await assert.rejects(f.adapter.authorizedPendingSlot(args),/inspection_unavailable/);assert.equal(f.releases.length,1);assert.ok(f.releases[0] instanceof Error);
 }
});
test('commit uncertainty rejects success and permits idempotent retry',async()=>{
 const f=fixture({fail:sql=>sql==='COMMIT'});await assert.rejects(f.adapter.authorizedPendingSlot(args),/inspection_unavailable/);assert.equal(f.calls.at(-1).sql,'ROLLBACK');assert.equal(f.releases.length,1);
});
test('pool errors and unexpected database shape fail closed',async()=>{
 const f=fixture({connectFails:true});await assert.rejects(f.adapter.authorizedPendingSlot(args),e=>e.message==='inspection_unavailable');
 for(const result of [{rowCount:0,rows:[]},{rowCount:2,rows:[{value:{}}]},{rowCount:1,rows:[{value:[]}] }])await assert.rejects(fixture({result}).adapter.authorizedPendingSlot(args),/inspection_unavailable/);
 assert.equal(await fixture({result:{rowCount:1,rows:[{value:'true'}]}}).adapter.commitReceiptAtomically({proof:proof(),expectedState:'prepared'}),false);
});
