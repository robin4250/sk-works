import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createQualificationVersionedStorageReader} from './qualification_management_storage_reader.mjs';
const projectRef='a'.repeat(20),id='00000000-0000-0000-0000-000000000001',version='00000000-0000-0000-0000-000000000002',bytes=new TextEncoder().encode('fixture-only-file');
const args={bucket:'qualification-certificates',path:`${id}/${id}/${id}/management/${id}/photo.png`,objectId:id,version,maxBytes:20971520,expectedBytes:bytes.length,expectedSha256:createHash('sha256').update(bytes).digest('hex')};
const meta=()=>({id,version,bucket:args.bucket,path:args.path,archived:false,deleted:false});
function fixture(overrides={}){const calls=[];const read=createQualificationVersionedStorageReader({projectRef,verifiedDeployment:{projectRef,restVersionId:true,sourceCommit:'b'.repeat(40)},accessTokenProvider:async()=> 'fixture-token',readMetadata:async()=>meta(),fetchImpl:async(url,options)=>{calls.push({url,options});return new Response(bytes,{status:200,headers:{'content-length':String(bytes.length)}});},...overrides});return{read,calls};}
test('unknown deployed version query capability fails closed before download',()=>{
 assert.throws(()=>fixture({verifiedDeployment:null}),/storage_snapshot_unavailable/);
 assert.throws(()=>fixture({verifiedDeployment:{projectRef,restVersionId:false,sourceCommit:'b'.repeat(40)}}),/storage_snapshot_unavailable/);
});
test('version query, fixed origin and credentials bind a bounded verified byte snapshot',async()=>{
 const {read,calls}=fixture();const actual=await read(args);assert.deepEqual(actual.bytes,bytes);assert.equal(actual.objectId,id);assert.equal(actual.version,version);
 assert.equal(calls[0].url.origin,`https://${projectRef}.supabase.co`);assert.equal(calls[0].url.searchParams.get('versionId'),version);assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.cache,'no-store');assert.equal(calls[0].options.headers.authorization,'Bearer fixture-token');
});
test('wrong identity and changed metadata around a read reject all bytes',async()=>{
 for(const change of [{id:version},{version:id},{archived:true},{deleted:true},{path:'other'}]){let reads=0;const f=fixture({readMetadata:async()=>++reads===1?meta():{...meta(),...change}});await assert.rejects(f.read(args),e=>e.message==='storage_snapshot_unavailable');}
 const f=fixture({readMetadata:async()=>null});await assert.rejects(f.read(args),/storage_snapshot_unavailable/);assert.equal(f.calls.length,0);
});
test('stale CDN or unsupported query that returns different content is rejected by actual SHA',async()=>{
 const f=fixture({fetchImpl:async()=>new Response(new Uint8Array(bytes.length).fill(42),{status:200})});await assert.rejects(f.read(args),/storage_snapshot_unavailable/);
});
test('redirect/range/compressed/oversized/truncated responses do not fall back',async()=>{
 const responses=[()=>new Response(bytes,{status:206}),()=>new Response(bytes,{status:302,headers:{location:'https://evil.invalid'}}),()=>new Response(bytes,{headers:{'content-encoding':'gzip'}}),()=>new Response(bytes,{headers:{'content-length':'99999'}}),()=>new Response(bytes.slice(1)),()=>new Response(new Uint8Array(bytes.length+1))];
 for(const response of responses){let calls=0;const f=fixture({fetchImpl:async()=>{calls++;return response();}});await assert.rejects(f.read(args),/storage_snapshot_unavailable/);assert.equal(calls,1);}
});
test('unsafe path/version inputs and secret dependency errors are not exposed',async()=>{
 const f=fixture();for(const change of [{path:'../private'},{path:'a//b'},{version:'unknown'},{objectId:{toString:()=>id}},{expectedSha256:{toString:()=>args.expectedSha256}},{expectedBytes:20971521},{bucket:'other'}])await assert.rejects(f.read({...args,...change}),/storage_snapshot_unavailable/);assert.equal(f.calls.length,0);
 await assert.rejects(fixture({accessTokenProvider:async()=>{throw Error('secret-token');}}).read(args),e=>e.message==='storage_snapshot_unavailable');
});
test('deadline aborts body download and returns no partial file',async()=>{
 let cancelled=false;const body=new ReadableStream({start(c){c.enqueue(bytes.slice(0,4));},cancel(){cancelled=true;}});
 await assert.rejects(fixture({timeoutMs:15,fetchImpl:async()=>new Response(body)}).read(args),/storage_snapshot_unavailable/);assert.equal(cancelled,true);
});
test('a credential provider finishing after deadline cannot start a late download',async()=>{
 let resolveToken;const f=fixture({timeoutMs:15,accessTokenProvider:()=>new Promise(resolve=>{resolveToken=resolve;})});
 await assert.rejects(f.read(args),/storage_snapshot_unavailable/);resolveToken('fixture-token');
 await new Promise(resolve=>setImmediate(resolve));assert.equal(f.calls.length,0);
});
