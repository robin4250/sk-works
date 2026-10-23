// Actual TLS handshakes against loopback only; no PostgreSQL/project connection.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import tls from 'node:tls';
import {execFileSync} from 'node:child_process';
import {connectionOptions,HOST} from './production_transport_core.mjs';
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'sko-expense-tls-fixture-'));
const openssl=args=>execFileSync('openssl',args,{cwd:dir,stdio:'ignore'});
try {
 openssl(['req','-x509','-newkey','rsa:2048','-nodes','-keyout','ca.key','-out','ca.crt','-days','1','-subj','/CN=isolated-fixture-CA']);
 for(const [name,host] of [['valid',HOST],['wrong','other.invalid']]){
  openssl(['req','-newkey','rsa:2048','-nodes','-keyout',name+'.key','-out',name+'.csr','-subj','/CN='+host]);
  fs.writeFileSync(path.join(dir,name+'.ext'),'subjectAltName=DNS:'+host+'\nextendedKeyUsage=serverAuth\n');
  openssl(['x509','-req','-in',name+'.csr','-CA','ca.crt','-CAkey','ca.key','-CAcreateserial','-out',name+'.crt','-days','1','-extfile',name+'.ext']);
 }
 const attempt=async(name,trust)=>{
  const server=tls.createServer({key:fs.readFileSync(path.join(dir,name+'.key')),cert:fs.readFileSync(path.join(dir,name+'.crt'))},socket=>socket.end());
  server.on('tlsClientError',()=>{});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
   return await new Promise(resolve=>{
    // Only the test socket target/fixture CA differ. The production SSL policy
    // object, including fixed SNI/hostname and verification, is used unchanged.
    const options={...connectionOptions('synthetic-fixture-only').ssl,host:'127.0.0.1',port:server.address().port};
    if(trust) options.ca=fs.readFileSync(path.join(dir,'ca.crt'));
    const socket=tls.connect(options,()=>{const accepted=socket.authorized===true;socket.destroy();resolve(accepted);});
    socket.on('error',()=>{socket.destroy();resolve(false);});
    socket.setTimeout(3000,()=>{socket.destroy();resolve(false);});
   });
  }finally{await new Promise(resolve=>server.close(resolve));}
 };
 assert.equal(await attempt('valid',true),true);
 assert.equal(await attempt('valid',false),false,'untrusted issuer refused');
 assert.equal(await attempt('wrong',true),false,'trusted wrong-project certificate refused');
 console.log('PASS actual loopback TLS: fixed project hostname accepted only under explicit fixture trust; untrusted/wrong-project certificates refused');
}finally{fs.rmSync(dir,{recursive:true,force:true});}
