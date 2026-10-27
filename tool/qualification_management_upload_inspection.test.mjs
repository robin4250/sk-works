import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createQualificationUploadInspector} from './qualification_management_upload_inspection.mjs';
const id=n=>`40000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function fixture(){
 const ids=Object.fromEntries(['actorId','sessionId','companyId','workerId','qualificationMasterId','targetId','requestId','slotId','objectId'].map((k,i)=>[k,id(i+1)]));
 const p={...ids,contract:'qualification_management_upload_v1',state:'prepared',bucket:'qualification-certificates',objectVersion:'v1',declaredBytes:12,mime:'image/png'};
 p.path=`${p.companyId}/${p.workerId}/${p.targetId}/management/${p.requestId}/new.png`;
 const f={p,bytes:Uint8Array.from([137,80,78,71,13,10,26,10,1,2,3,4]),proofs:[],session:{active:true,anonymous:false,actorId:p.actorId,sessionId:p.sessionId}};
 p.declaredSha256=createHash('sha256').update(f.bytes).digest('hex');
 f.make=({parser=async()=>true,reader}={})=>createQualificationUploadInspector({verifySession:async()=>f.session,db:{authorizedPendingSlot:async()=>p,commitReceiptAtomically:async({proof})=>{f.proofs.push(proof);return true;}},storage:{readSelectedVersion:reader??(async()=>({bytes:f.bytes,version:p.objectVersion,objectId:p.objectId}))},validateFile:parser});
 f.call=fn=>fn({bearerToken:'fixture-only',requestId:p.requestId,slotId:p.slotId});return f;
}
test('trusted bytes bind every qualification identity and commit exact receipt',async()=>{const f=fixture();assert.equal((await f.call(f.make())).inspected,true);assert.equal(f.proofs.length,1);assert.match(f.proofs[0].sha256,/^[a-f0-9]{64}$/);assert.equal(f.proofs[0].targetId,f.p.targetId);});
test('anonymous or different actor/session never produces receipt',async()=>{for(const patch of [{anonymous:true},{actorId:id(99)},{sessionId:id(98)},{active:false}]){const f=fixture();f.session={...f.session,...patch};await assert.rejects(f.call(f.make()));assert.equal(f.proofs.length,0);}});
test('unrelated bucket/path/version/object and parser rejection fail closed',async()=>{for(const kind of ['bucket','path','version','object','parser']){const f=fixture();if(kind==='bucket')f.p.bucket='worker-documents';if(kind==='path')f.p.path='foreign/path';const inspect=f.make({parser:async()=>kind!=='parser',reader:async()=>({bytes:f.bytes,version:kind==='version'?'v2':'v1',objectId:kind==='object'?id(77):f.p.objectId})});await assert.rejects(f.call(inspect));assert.equal(f.proofs.length,0);}});
test('parser mutation and MIME/size mismatch cannot create trusted proof',async()=>{for(const kind of ['mutation','mime','size']){const f=fixture();if(kind==='mime')f.p.mime='image/jpeg';if(kind==='size')f.p.declaredBytes++;await assert.rejects(f.call(f.make({parser:async({bytes})=>{if(kind==='mutation')bytes[9]++;return true;}})));assert.equal(f.proofs.length,0);}});
test('unknown contract/state, oversized path and coercible UUID objects are refused',async()=>{for(const kind of ['contract','state','longpath','coercion']){const f=fixture();if(kind==='contract')f.p.contract='worker_document_upload';if(kind==='state')f.p.state='approved';if(kind==='longpath')f.p.path+='a'.repeat(1025);if(kind==='coercion')f.session.actorId={toString:()=>f.p.actorId};await assert.rejects(f.call(f.make()));assert.equal(f.proofs.length,0);}});
test('mutation of trusted-reader source bytes during parser execution is refused',async()=>{const f=fixture();await assert.rejects(f.call(f.make({parser:async()=>{f.bytes[9]++;return true;}})));assert.equal(f.proofs.length,0);});
test('commit rejection or exception cannot report inspection success',async()=>{for(const fail of ['false','throw']){const f=fixture();const inspect=createQualificationUploadInspector({verifySession:async()=>f.session,db:{authorizedPendingSlot:async()=>f.p,commitReceiptAtomically:async()=>{if(fail==='throw')throw Error('fixture lost commit');return false;}},storage:{readSelectedVersion:async()=>({bytes:f.bytes,version:f.p.objectVersion,objectId:f.p.objectId})},validateFile:async()=>true});await assert.rejects(f.call(inspect));}});

test('pending identity is frozen across asynchronous parsing',async()=>{const f=fixture();const object={bytes:f.bytes,version:'v1',objectId:f.p.objectId};await assert.rejects(f.call(f.make({reader:async()=>object,parser:async()=>{f.p.objectVersion='v2';object.version='v2';return true;}})));assert.equal(f.proofs.length,0);});

test('prepared selected-byte hash must match inspected actual bytes',async()=>{const f=fixture();f.p.declaredSha256='b'.repeat(64);await assert.rejects(f.call(f.make()));assert.equal(f.proofs.length,0);});
test('selected declaration is passed to reader and malformed declaration never downloads',async()=>{
 const f=fixture();let observed;await f.call(f.make({reader:async input=>{observed=input;return{bytes:f.bytes,version:f.p.objectVersion,objectId:f.p.objectId};}}));assert.equal(observed.expectedBytes,f.p.declaredBytes);assert.equal(observed.expectedSha256,f.p.declaredSha256);
 for(const patch of [{declaredBytes:NaN},{declaredBytes:20971521},{declaredSha256:{toString:()=>f.p.declaredSha256}},{mime:'text/html'}]){const other=fixture();Object.assign(other.p,patch);let reads=0;await assert.rejects(other.call(other.make({reader:async()=>{reads++;}})));assert.equal(reads,0);}
});
test('legacy unqualified storage method cannot be silently used',()=>{
 assert.throws(()=>createQualificationUploadInspector({verifySession:async()=>{},validateFile:async()=>true,db:{authorizedPendingSlot:async()=>{},commitReceiptAtomically:async()=>true},storage:{readImmutableVersion:async()=>{}}}),/inspection_unavailable/);
});
