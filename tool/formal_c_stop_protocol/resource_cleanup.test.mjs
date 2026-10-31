// Failure-injection cleanup only. Does not stand in for Native database proof.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
for(const phase of ['connect','set'])for(const index of [1,2,3])test(`${phase} failure at client ${index} closes every allocated client`,async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'formal-c-cleanup-'));
 try{
  const module=path.join(dir,'fake-driver.mjs');
  await fs.writeFile(module,`let next=0;export class Client{constructor(){this.index=++next;}async connect(){if('${phase}'==='connect'&&this.index===${index})throw Error('synthetic connect failure');}async query(sql){if(sql.startsWith('set ')&&'${phase}'==='set'&&this.index===${index})throw Error('synthetic timeout setup failure');return{rows:[]};}async end(){}}`,{flag:'wx',mode:0o600});
  const result=spawnSync(process.execPath,[fileURLToPath(new URL('./native-protocol-fixture.mjs',import.meta.url)),pathToFileURL(module).href],{encoding:'utf8',timeout:5000,env:{SKO_STOP_FIXTURE_URL:'postgresql://postgres:fixture-only@127.0.0.1:5432/sko_stop_fixture'}});
  assert.equal(result.status,1);assert.equal(result.signal,null);
  const receipt=JSON.parse(result.stdout.trim());
  assert.equal(receipt.fixture_clients_allocated,index);assert.equal(receipt.fixture_cleanup_calls,index);
  assert.equal(receipt.fixture_connections_opened,phase==='connect'?index-1:index);
  assert.equal(receipt.fixture_connections_closed,receipt.fixture_connections_opened);
  assert.equal(receipt.production_changed,false);
 }finally{await fs.rm(dir,{recursive:true,force:true});}
});
