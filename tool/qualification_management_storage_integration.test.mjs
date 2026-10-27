import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createQualificationUploadInspector} from './qualification_management_upload_inspection.mjs';
import {createQualificationVersionedStorageReader} from './qualification_management_storage_reader.mjs';

// Synthetic bytes and dependency fakes only. No production requests, credentials,
// parser installation or trusted-deployment evidence are supplied by this test.
const uuid=n=>`50000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
function fixture({mode='success'}={}) {
  const ids=Object.fromEntries(['actorId','sessionId','companyId','workerId','qualificationMasterId','targetId','requestId','slotId','objectId'].map((key,i)=>[key,uuid(i+1)]));
  const bytes=Uint8Array.from([137,80,78,71,13,10,26,10,7,8,9,10]);
  const sha=createHash('sha256').update(bytes).digest('hex');
  const pending={...ids,contract:'qualification_management_upload_v1',state:'prepared',bucket:'qualification-certificates',objectVersion:uuid(30),declaredBytes:bytes.length,declaredSha256:sha,mime:'image/png'};
  pending.path=`${ids.companyId}/${ids.workerId}/${ids.targetId}/management/${ids.requestId}/${ids.slotId}.png`;
  const proofCalls=[],parserCalls=[],fetchCalls=[];let metadataCalls=0;
  const storageOptions={
    projectRef:'abcdefghijklmnopqrst',
    verifiedDeployment:{projectRef:'abcdefghijklmnopqrst',restVersionId:mode!=='unknown-deployment',sourceCommit:'a'.repeat(40)},
    timeoutMs:mode==='timeout'?20:5000,
    accessTokenProvider:async()=> 'synthetic-bearer-only',
    readMetadata:async scope=>{
      metadataCalls++;
      assert.deepEqual(scope,{bucket:pending.bucket,path:pending.path,objectId:ids.objectId,version:pending.objectVersion});
      return {id:ids.objectId,version:mode==='wrong-version'||(mode==='metadata-race'&&metadataCalls===2)?uuid(31):pending.objectVersion,bucket:pending.bucket,path:pending.path,archived:false,deleted:false};
    },
    fetchImpl:async(url,options)=>{
      fetchCalls.push({url:String(url),options});
      assert.equal(options.redirect,'error');
      assert.equal(url.searchParams.get('versionId'),pending.objectVersion);
      assert.equal(url.hostname,'abcdefghijklmnopqrst.supabase.co');
      if(mode==='timeout')return new Response(new ReadableStream({start(){},cancel(){}}),{status:200});
      const served=Uint8Array.from(bytes);if(mode==='wrong-hash')served[9]++;
      return new Response(served,{status:200,headers:{'content-length':String(bytes.length),'content-type':'image/png'}});
    },
  };
  const make=()=> {
    const readSelectedVersion=createQualificationVersionedStorageReader(storageOptions);
    return createQualificationUploadInspector({
      verifySession:async token=>{assert.equal(token,'synthetic-session-only');return {active:true,anonymous:false,actorId:ids.actorId,sessionId:ids.sessionId};},
      db:{authorizedPendingSlot:async scope=>{assert.deepEqual(scope,{actorId:ids.actorId,sessionId:ids.sessionId,requestId:ids.requestId,slotId:ids.slotId});return pending;},commitReceiptAtomically:async command=>{proofCalls.push(command);return true;}},
      storage:{readSelectedVersion},
      validateFile:async file=>{parserCalls.push(file);assert.deepEqual(file.bytes,bytes);assert.equal(file.mime,'image/png');return true;},
    });
  };
  return {ids,bytes,pending,sha,proofCalls,parserCalls,fetchCalls,make,call:fn=>fn({bearerToken:'synthetic-session-only',requestId:ids.requestId,slotId:ids.slotId}),metadataCount:()=>metadataCalls};
}

test('real reader and inspector bind exact parsed bytes to one scoped receipt',async()=>{
  const f=fixture();
  assert.deepEqual(await f.call(f.make()),{inspected:true,requestId:f.ids.requestId,slotId:f.ids.slotId});
  assert.equal(f.fetchCalls.length,1);assert.equal(f.metadataCount(),2);assert.equal(f.parserCalls.length,1);assert.equal(f.proofCalls.length,1);
  assert.deepEqual(f.proofCalls[0],{expectedState:'prepared',proof:{contract:f.pending.contract,...f.ids,bucket:f.pending.bucket,path:f.pending.path,objectVersion:f.pending.objectVersion,mime:'image/png',bytes:f.bytes.length,sha256:f.sha}});
});

for(const mode of ['metadata-race','wrong-version','wrong-hash','timeout']) {
  test(`real reader and inspector refuse ${mode} before any receipt`,async()=>{
    const f=fixture({mode});await assert.rejects(f.call(f.make()));
    assert.equal(f.proofCalls.length,0);assert.equal(f.parserCalls.length,0);
    assert.equal(f.fetchCalls.length,mode==='wrong-version'?0:1);
  });
}

test('unknown deployment refuses integration construction without network or receipt',()=>{
  const f=fixture({mode:'unknown-deployment'});assert.throws(f.make,/storage_snapshot_unavailable/);
  assert.equal(f.fetchCalls.length,0);assert.equal(f.parserCalls.length,0);assert.equal(f.proofCalls.length,0);
});
