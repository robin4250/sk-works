import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {request as httpsRequest} from 'node:https';
import {createWitnessHttpsCandidate} from '../src/recovery-witness-https-candidate.mjs';
import {TestWitness} from './recovery-witness-sqlite-fixture.mjs';
import {validateWitnessReceipt} from '../src/recovery-witness-model.mjs';

const signing=generateKeyPairSync('ed25519'),key=signing.publicKey.export({format:'jwk'});
const endpoint='https://witness.local/receipt',bearer='synthetic-witness-TLS-credential';
const input={operation:'consume',scope:'fixture',nonce:'a'.repeat(64),proposalHash:'b'.repeat(64),challenge:'c'.repeat(64)};
async function fixture({wrap=x=>x,timeoutMs=1000,maxConcurrent=2}={}) {
  const directory=mkdtempSync(join(tmpdir(),'witness-real-tls-'));
  const keyPath=join(directory,'tls.key'),certPath=join(directory,'tls.crt');
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1',
    '-keyout',keyPath,'-out',certPath,'-subj','/CN=witness.local',
    '-addext','subjectAltName=DNS:witness.local'],{stdio:'ignore'});
  const cert=readFileSync(certPath),witness=new TestWitness(join(directory,'ledger.db'),signing.privateKey);
  const server=createWitnessHttpsCandidate({endpoint,bearer,scopes:['fixture'],key,
    authority:wrap(witness),now:()=>1000,timeoutMs,maxConcurrent,tls:{key:readFileSync(keyPath),cert}});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const send=(data=input,options={})=>new Promise((resolve,reject)=>{
    const body=typeof data==='string'?data:JSON.stringify(data);
    // Explicit local transport bridge: the configured origin and certificate
    // name remain witness.local; only the socket connects to this fixture port.
    const req=httpsRequest({hostname:'127.0.0.1',port:server.address().port,servername:'witness.local',
      ca:cert,method:'POST',path:'/receipt',agent:false,
      headers:{host:'witness.local',authorization:`Bearer ${bearer}`,'content-type':'application/json'},...options},res=>{
      const chunks=[];res.on('data',x=>chunks.push(x));res.on('end',()=>resolve({status:res.statusCode,
        headers:res.headers,body:Buffer.concat(chunks).toString('utf8')}));res.on('error',reject);
    });
    req.setTimeout(2000,()=>req.destroy(Error('fixture timeout')));req.on('error',reject);req.end(body);
  });
  return {server,witness,send,async close(){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));witness.close();rmSync(directory,{recursive:true,force:true});}};
}

test('TLS client verifies certificate and consumes once with explicit fresh lookup',async()=>{
  const f=await fixture();try{
    const first=await f.send();assert.equal(first.status,200);
    const receipt=JSON.parse(first.body);
    assert.equal(validateWitnessReceipt(receipt,{...input,key,now:1000,minSequence:1}).sequence,1);
    assert.equal(first.headers['cache-control'],'no-store');
    assert.equal((await f.send({...input,operation:'lookup',challenge:'d'.repeat(64)})).status,200);
    assert.equal((await f.send()).status,503);
    assert.equal(f.witness.db.prepare('select count(*) n from consumed').get().n,1);
    await assert.rejects(f.send(input,{ca:undefined}));
    await assert.rejects(f.send(input,{maxVersion:'TLSv1.2'}));
  }finally{await f.close();}
});
test('host, path, authentication and bounded input reject before consumption',async()=>{
  const f=await fixture();try{
    assert.equal((await f.send(input,{headers:{host:'other.local'}})).status,404);
    assert.equal((await f.send(input,{path:'/receipt?alternate=1'})).status,404);
    assert.equal((await f.send(input,{method:'GET'})).status,404);
    assert.equal((await f.send(input,{headers:{host:'witness.local','content-type':'application/json',authorization:'Bearer wrong'}})).status,401);
    assert.equal((await f.send('x'.repeat(3000),{headers:{host:'witness.local','content-type':'application/json',authorization:`Bearer ${bearer}`,'content-length':'3000'}})).status,413);
    assert.equal(f.witness.db.prepare('select count(*) n from consumed').get().n,0);
  }finally{await f.close();}
});
test('concurrent admission rejects excess work before the authority and retains one result',async()=>{
  let release,entered;const waiting=new Promise(resolve=>{entered=resolve;}),gate=new Promise(resolve=>{release=resolve;});let calls=0;
  const f=await fixture({maxConcurrent:1,wrap:witness=>({lookup:args=>witness.lookup(args),consume:async args=>{calls++;entered();await gate;return witness.consume(args);}})});
  try {
    const first=f.send();await waiting;
    assert.equal((await f.send()).status,503);assert.equal(calls,1);
    release();assert.equal((await first).status,200);assert.equal(calls,1);
  }finally{release();await f.close();}
});
test('authority deadline settles over a real TLS socket without retry or secret errors',async()=>{
  let calls=0;const f=await fixture({timeoutMs:100,wrap:()=>({lookup(){throw Error('unused');},consume(){calls++;return new Promise(()=>{});}})});
  try{
    const response=await f.send();assert.equal(response.status,503);assert.equal(calls,1);
    assert.equal(response.body.includes(bearer),false);
  }finally{await f.close();}
});
