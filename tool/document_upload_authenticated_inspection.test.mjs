import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createAuthenticatedDocumentUploadInspection } from './document_upload_authenticated_inspection.mjs';
const id = n => `60000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
function fixture() {
  const bytes = Uint8Array.from([137,80,78,71,13,10,26,10,1,2,3,4]);
  const p = Object.fromEntries(['actorId','sessionId','companyId','workerId','requirementId','targetId','requestId','uploadId','objectId'].map((k,i)=>[k,id(i+1)]));
  Object.assign(p,{contract:'worker_document_upload_v2',status:'awaiting_inspection',bucket:'worker-documents',objectVersion:'v1',mime:'image/png',declaredBytes:bytes.length,declaredSha256:createHash('sha256').update(bytes).digest('hex')});
  p.path=`${p.companyId}/${p.workerId}/${p.requirementId}/${p.requestId}/new.png`;
  const f={p,bytes,session:{active:true,anonymous:false,actorId:p.actorId,sessionId:p.sessionId},writes:[],reads:0,valid:true,commit:true};
  f.make=({reader,parser}={})=>createAuthenticatedDocumentUploadInspection({verifySession:async()=>f.session,db:{authorizedPendingUpload:async scope=>{f.scope=scope;return p;},commitInspectionAtomically:async value=>{f.writes.push(value);return f.commit;}},storage:{readImmutableVersion:reader??(async()=>{f.reads++;return{objectId:p.objectId,version:p.objectVersion,bytes:f.bytes};})},validateFile:parser??(async()=>f.valid)});
  f.call=fn=>fn({bearerToken:'synthetic-only',requestId:p.requestId,uploadId:p.uploadId});return f;
}
test('verified session and exact object bytes produce only the bound receipt',async()=>{const f=fixture();assert.deepEqual(await f.call(f.make()),{inspected:true,requestId:f.p.requestId,uploadId:f.p.uploadId});assert.equal(f.writes.length,1);assert.equal(f.writes[0].scope.sessionId,f.session.sessionId);assert.equal(f.writes[0].pending.targetId,f.p.targetId);});
test('anonymous, stale or foreign session cannot reach Storage',async()=>{for(const patch of [{active:false},{anonymous:true},{actorId:id(90)},{sessionId:id(91)}]){const f=fixture();Object.assign(f.session,patch);await assert.rejects(f.call(f.make()));assert.equal(f.reads,0);assert.equal(f.writes.length,0);}});
test('wrong tenant/path/contract/state or declared content cannot commit',async()=>{for(const patch of [{path:'foreign/new.png'},{bucket:'qualification-certificates'},{contract:'legacy'},{status:'approved'},{declaredBytes:13},{declaredSha256:'a'.repeat(64)}]){const f=fixture();Object.assign(f.p,patch);await assert.rejects(f.call(f.make()));assert.equal(f.writes.length,0);}});
test('reader cannot substitute object identity, version, or bytes',async()=>{for(const kind of ['id','version','bytes']){const f=fixture();await assert.rejects(f.call(f.make({reader:async()=>({objectId:kind==='id'?id(99):f.p.objectId,version:kind==='version'?'v2':'v1',bytes:kind==='bytes'?Uint8Array.from([...f.bytes.slice(0,-1),99]):f.bytes})})));assert.equal(f.writes.length,0);}});
test('parser rejection or mutation cannot commit',async()=>{for(const mutate of [false,true]){const f=fixture();await assert.rejects(f.call(f.make({parser:async({bytes})=>{if(mutate)bytes[9]++;return mutate;}})));assert.equal(f.writes.length,0);}});
test('DB terminal conflict cannot be represented as success',async()=>{const f=fixture();f.commit=false;await assert.rejects(f.call(f.make()),/inspection_conflict/);assert.equal(f.writes.length,1);});
test('mutated authorized source cannot silently replace the frozen pending scope',async()=>{const f=fixture();const original=f.p.targetId;await f.call(f.make({parser:async()=>{f.p.targetId=id(99);return true;}}));assert.equal(f.writes[0].pending.targetId,original);});
test('missing trusted dependencies fail closed',()=>{assert.throws(()=>createAuthenticatedDocumentUploadInspection({}));});
