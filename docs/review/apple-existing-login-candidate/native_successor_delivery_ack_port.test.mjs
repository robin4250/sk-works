import test from 'node:test';
import assert from 'node:assert/strict';
import {createSuccessorDeliveryAckPorts} from './native_successor_delivery_ack_port.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const row=(status='server_completed')=>({schema:1,request_id:id(1),status,retry_allowed:false,application_adoption_confirmed:false});
function fixture(){
 const calls=[],claims={role:'authenticated',sub:id(2),session_id:id(3),exp:1800001000};
 const db={query:async(q,p)=>{calls.push({q,p});return {rows:q.includes('acknowledge_successor_possession')?[{r:row('successor_possession_recorded')}]:[{r:row()}]};},release:()=>calls.push({q:'release'})};
 const config={enabled:true,reviewed:true,now:()=>1800000000000,pool:{connect:async()=>db},
  authenticateExactBearer:async()=>({claims,user:{id:id(2),is_anonymous:false}})};
 return {calls,claims,db,config,input:{request_id:id(1),exactBearer:'synthetic-successor-bearer'}};
}
test('OFF, malformed/forged extra metadata and failed Auth never open a database connection',async()=>{
 for(const patch of [{enabled:false},{reviewed:false},{authenticateExactBearer:async()=>{throw Error('synthetic-secret');}}]){
  const f=fixture();await assert.rejects(createSuccessorDeliveryAckPorts({...f.config,...patch}).status(f.input),/reconciliation_unavailable/);assert.equal(f.calls.length,0);
 }
 for(const input of [{request_id:id(1),exactBearer:'synthetic-successor-bearer',successor_session_id:id(9)},
  {request_id:{toString:()=>id(1)},exactBearer:'synthetic-successor-bearer'},
  Object.create({request_id:id(1),exactBearer:'synthetic-successor-bearer'})]){
  const f=fixture();await assert.rejects(createSuccessorDeliveryAckPorts(f.config).status(input));assert.equal(f.calls.length,0);
 }
 const f=fixture(),getter={request_id:id(1),get exactBearer(){throw Error('secret');}};
 await assert.rejects(createSuccessorDeliveryAckPorts(f.config).status(getter),/reconciliation_unavailable/);assert.equal(f.calls.length,0);
});
test('server Auth UID/SID are snapshotted before pool awaits and bearer never enters SQL',async()=>{
 const f=fixture(),original=f.config.pool.connect;
 f.config.pool.connect=async()=>{f.claims.sub=id(8);f.claims.session_id=id(9);return original();};
 const result=await createSuccessorDeliveryAckPorts(f.config).status(f.input);
 assert.deepEqual(result,row());assert.ok(Object.isFrozen(result));
 const q=f.calls.find(c=>c.q.includes('successor_delivery_status'));assert.deepEqual(q.p,[id(1),id(2),id(3)]);
 const context=JSON.parse(f.calls.find(c=>c.q.includes('set_config')).p[0]);
 assert.equal(context.sub,id(2));assert.equal(context.session_id,id(3));
 assert.equal(JSON.stringify(f.calls).includes('synthetic-successor-bearer'),false);
 assert.deepEqual(f.calls.slice(-2).map(c=>c.q),['commit','release']);
});
test('request mutation while Auth is pending cannot replace the selected request',async()=>{
 const f=fixture();f.config.authenticateExactBearer=async()=>{f.input.request_id=id(9);return {claims:f.claims,user:{id:id(2)}};};
 assert.equal((await createSuccessorDeliveryAckPorts(f.config).status(f.input)).request_id,id(1));
});
test('wrong Auth identity, anonymous, expired or malformed claims deny before database use',async()=>{
 for(const patch of [{user:{id:id(9)}},{user:{id:id(2),is_anonymous:true}},
  {claims:{role:'authenticated',sub:id(2),session_id:id(3),exp:1}},
  {claims:{role:'service_role',sub:id(2),session_id:id(3),exp:1800001000}},
  {claims:{role:'authenticated',sub:id(2),session_id:{toString:()=>id(3)},exp:1800001000}}]){
  const f=fixture();f.config.authenticateExactBearer=async()=>({claims:f.claims,user:{id:id(2)},...patch});
  await assert.rejects(createSuccessorDeliveryAckPorts(f.config).acknowledge(f.input));assert.equal(f.calls.length,0);
 }
});
test('foreign/extra/adoption-confirmed SQL responses fail closed and roll back',async()=>{
 for(const wrong of [{...row(),request_id:id(9)},{...row(),application_adoption_confirmed:true},
  {...row(),access_token:'synthetic-secret'},row()]){
  const f=fixture(),original=f.db.query;
  f.db.query=async(q,p)=>q.includes('acknowledge_successor_possession')?{rows:[{r:wrong}]}:original(q,p);
  await assert.rejects(createSuccessorDeliveryAckPorts(f.config).acknowledge(f.input));
  assert.ok(f.calls.some(c=>c.q==='rollback'));assert.ok(!f.calls.some(c=>c.q==='commit'));
 }
});
test('ACK success is possession-only and commit uncertainty returns a generic error',async()=>{
 const f=fixture();assert.deepEqual(await createSuccessorDeliveryAckPorts(f.config).acknowledge(f.input),row('successor_possession_recorded'));
 const g=fixture(),original=g.db.query;g.db.query=async(q,p)=>{if(q==='commit')throw Error('synthetic-commit-secret');return original(q,p);};
 await assert.rejects(createSuccessorDeliveryAckPorts(g.config).acknowledge(g.input),e=>e.message==='apple_successor_reconciliation_unavailable');
 assert.ok(g.calls.some(c=>c.q==='rollback'));assert.equal(g.calls.at(-1).q,'release');
});
