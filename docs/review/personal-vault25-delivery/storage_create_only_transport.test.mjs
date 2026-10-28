import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createVaultCreateOnlyUpload} from './storage_create_only_transport.mjs';
const bytes=()=>Buffer.from('%PDF-1.7\nsynthetic-own-document\n%%EOF\n');
const request=()=>{const data=bytes();return {ownerId:'00000000-0000-0000-0000-000000000001',
  artifactKey:'a'.repeat(64),pdfSha256:createHash('sha256').update(data).digest('hex'),bytes:data};};
const config={origin:'https://fixture.invalid',bucket:'vault',publishableKey:'sb_publishable_fixture',
  authorizationHeader:async()=>'Bearer synthetic.token'};

test('one create-only POST preserves exact PDF; acknowledgement is not an immutable/privacy receipt',async()=>{
  let calls=0;const input=request();
  const upload=createVaultCreateOnlyUpload({...config,fetchImpl:async(url,options)=>{
    calls++;assert.equal(url,`https://fixture.invalid/storage/v1/object/vault/personal-vault/${input.ownerId}/${input.artifactKey}.pdf`);
    assert.equal(options.method,'POST');assert.equal(options.headers['x-upsert'],'false');
    assert.equal(options.headers['Content-Type'],'application/pdf');assert.equal(options.cache,'no-store');
    assert.equal(options.redirect,'error');assert.deepEqual(options.body,input.bytes);
    return new Response('{}',{status:200});}});
  const receipt=await upload(input);assert.equal(calls,1);assert.equal(receipt.status,'created_unverified');
  assert.equal('immutableVersion' in receipt,false);assert.equal('passed' in receipt,false);
});
test('existing object conflict never overwrites, retries, or reads untrusted provider errors',async()=>{
  let calls=0;let existing=Buffer.from('existing-signature-original');
  const upload=createVaultCreateOnlyUpload({...config,fetchImpl:async(_url,options)=>{
    calls++;if(options.headers['x-upsert']==='true')existing=Buffer.from(options.body);
    return new Response('provider-secret-should-not-leak',{status:400});}});
  await assert.rejects(upload(request()),{message:'vault_upload_outcome_unknown'});
  assert.equal(calls,1);assert.equal(existing.toString(),'existing-signature-original');
});
test('bytes are detached before authentication await',async()=>{
  const input=request(),expected=Buffer.from(input.bytes);let resolve;
  const auth=new Promise(r=>resolve=r);
  const upload=createVaultCreateOnlyUpload({...config,authorizationHeader:()=>auth,
    fetchImpl:async(_url,options)=>{assert.deepEqual(options.body,expected);return new Response('{}',{status:201});}});
  const result=upload(input);input.bytes.fill(0);resolve('Bearer synthetic.token');
  assert.equal((await result).pdfSha256,createHash('sha256').update(expected).digest('hex'));
});
test('invalid hash, oversized original and invalid path are rejected before auth or upload',async()=>{
  let calls=0;const upload=createVaultCreateOnlyUpload({...config,
    authorizationHeader:async()=>{calls++;return 'Bearer synthetic.token';},fetchImpl:async()=>{calls++;}});
  await assert.rejects(upload({...request(),pdfSha256:'b'.repeat(64)}),{message:'vault_upload_bytes_rejected'});
  await assert.rejects(upload({...request(),bytes:Buffer.alloc(6*1024*1024+1)}),{message:'vault_upload_request_invalid'});
  await assert.rejects(upload({...request(),ownerId:'../other-owner'}),{message:'vault_upload_request_invalid'});
  assert.equal(calls,0);
});
test('ignored abort and never-settling cancellation cannot hold deadline or trigger retries',async()=>{
  let calls=0;const upload=createVaultCreateOnlyUpload({...config,timeoutMs:10,
    fetchImpl:async()=>{calls++;return new Promise(()=>{});}});
  await assert.rejects(upload(request()),{message:'vault_upload_outcome_unknown'});assert.equal(calls,1);
  const cancel=createVaultCreateOnlyUpload({...config,timeoutMs:10,fetchImpl:async()=>({status:200,
    body:{cancel:()=>new Promise(()=>{})}})});
  assert.equal((await cancel(request())).status,'created_unverified');
});
test('redirect and network errors cannot forward credentials or claim success',async()=>{
  for(const fetchImpl of [async()=>({status:200,redirected:true}),async()=>{throw Error('Bearer SECRET');}]){
    await assert.rejects(createVaultCreateOnlyUpload({...config,fetchImpl})(request()),{message:'vault_upload_outcome_unknown'});
  }
});
