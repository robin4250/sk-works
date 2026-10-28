import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createVaultStorageDownload } from './storage_download_transport.mjs';
const bytes = Buffer.from('%PDF-1.7\nsynthetic own PDF\n%%EOF\n');
const digest = createHash('sha256').update(bytes).digest('hex');
const path = `personal-vault/00000000-0000-0000-0000-000000000001/${'a'.repeat(64)}.pdf`;
const opts = {maxBytes:bytes.length, expectedSha256:digest};
const config = {origin:'https://synthetic.supabase.co',bucket:'personal-documents',
  publishableKey:'sb_publishable_fixture',authorizationHeader:async()=> 'Bearer synthetic.jwt.fixture'};
const response = (body=bytes, headers={}) => new Response(body,
  {status:200,headers:{'content-type':'application/pdf',...headers}});

test('private GET uses bound bearer and streams exact receipt bytes', async () => {
  let request;
  const download = createVaultStorageDownload({...config,fetchImpl:async(...args)=>{
    request=args; return response();
  }});
  assert.deepEqual(await download(path,'saved-version',opts),bytes);
  assert.equal(request[0],`https://synthetic.supabase.co/storage/v1/object/personal-documents/${path}`);
  assert.equal(request[1].headers.Authorization,'Bearer synthetic.jwt.fixture');
  assert.equal(request[1].redirect,'manual');
  assert.equal(request[1].signal.aborted,true);
});

test('invalid receipt/path/key is refused without network', async () => {
  let calls=0;
  const download=createVaultStorageDownload({...config,fetchImpl:async()=>{calls++;return response();}});
  await assert.rejects(download('../other.pdf','v',opts),/vault_storage_request_invalid/);
  await assert.rejects(download(path,'v',{...opts,expectedSha256:null}),/vault_storage_request_invalid/);
  await assert.rejects(download(path,'v',{...opts,maxBytes:50*1024*1024+1}),/vault_storage_request_invalid/);
  assert.throws(()=>createVaultStorageDownload({...config,publishableKey:'sb_secret_fixture'}),/vault_storage_config_invalid/);
  assert.equal(calls,0);
});

test('size overflow, truncation, changed bytes, redirects and error bodies never return PDF', async () => {
  const cases=[
    response(Buffer.concat([bytes,Buffer.from('x')])), response(bytes.subarray(1)),
    response(Buffer.alloc(bytes.length)), new Response('secret provider error',{status:403}),
    new Response(null,{status:302,headers:{location:'https://other.example'}}),
    response(bytes,{'content-length':String(bytes.length+1)}),
    response(bytes,{'content-encoding':'gzip'}),
  ];
  for(const result of cases){
    let calls=0;
    const download=createVaultStorageDownload({...config,fetchImpl:async()=>{calls++;return result;}});
    await assert.rejects(download(path,'v',opts),/vault_(storage|stream)_/);
    assert.equal(calls,1);
  }
});

test('unresponsive fetch or reader/cancel cannot hold delivery open or retry', async () => {
  let fetchCalls=0;
  const download=createVaultStorageDownload({...config,timeoutMs:20,fetchImpl:()=>{
    fetchCalls++; return new Promise(()=>{});
  }});
  await assert.rejects(download(path,'v',opts),/vault_storage_timeout/);
  assert.equal(fetchCalls,1);
  let cancelCalls=0;
  const stalled=createVaultStorageDownload({...config,timeoutMs:20,fetchImpl:async()=>({
    status:200,headers:new Headers({'content-type':'application/pdf'}),
    body:{getReader:()=>({read:()=>new Promise(()=>{}),cancel:()=>{cancelCalls++;return new Promise(()=>{});}})},
  })});
  await assert.rejects(stalled(path,'v',opts),/vault_storage_timeout/);
  assert.equal(cancelCalls,1);
});
