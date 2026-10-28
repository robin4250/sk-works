import assert from 'node:assert/strict';
import net from 'node:net';
import {test,before,after} from 'node:test';
import {createNoticeCommitAckProxy} from './trade_document_notice_commit_ack_proxy.mjs';
const prior=process.env.CI;before(()=>{process.env.CI='true';});after(()=>{if(prior===undefined)delete process.env.CI;else process.env.CI=prior;});
const frame=(type,payload)=>{const b=Buffer.from(payload),h=Buffer.alloc(5);h[0]=type.charCodeAt(0);h.writeUInt32BE(b.length+4,1);return Buffer.concat([h,b]);};
async function scenario(t,respond,armed){
 const sockets=new Set(),backend=net.createServer(socket=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));socket.on('error',()=>{});socket.on('data',()=>respond(socket));});
 await new Promise(resolve=>backend.listen(0,'127.0.0.1',resolve));
 const target=`postgresql://postgres:fixture-only@127.0.0.1:${backend.address().port}/sko_document_consent_fixture`;
 const proxy=await createNoticeCommitAckProxy(target,{reviewOnly:true});
 const u=new URL(proxy.connectionString),client=net.connect({host:u.hostname,port:Number(u.port)});
 t.after(async()=>{client.destroy();await proxy.close();for(const socket of sockets)socket.destroy();await new Promise(resolve=>backend.close(resolve));});
 client.on('error',()=>{});await new Promise(resolve=>client.once('connect',resolve));
 // Send after acceptance; the backend's first bytes establish a ready pair.
 const started=new Promise(resolve=>client.once('data',resolve));
 client.write('startup');await started;
 if(armed)proxy.armCommitDrop();
 const chunks=[];client.on('data',chunk=>chunks.push(chunk));
 const ended=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{client.destroy();reject(Error('fixture peer did not close'));},3000);client.once('close',()=>{clearTimeout(timer);resolve();});});
 client.write('commit');await ended;
 return {proxy,bytes:Buffer.concat(chunks)};
}
test('rejects hosted/non-fixture targets and requires the explicit review gate',async()=>{
 for(const url of ['postgresql://postgres:fixture-only@example.com:5432/sko_document_consent_fixture','postgresql://postgres:fixture-only@127.0.0.1:5432/real_database','postgresql://postgres:other@127.0.0.1:5432/sko_document_consent_fixture'])await assert.rejects(createNoticeCommitAckProxy(url,{reviewOnly:true}),/isolated/);
 await assert.rejects(createNoticeCommitAckProxy('postgresql://postgres:fixture-only@127.0.0.1:5432/sko_document_consent_fixture'),/isolated/);
});
test('unarmed proxy forwards complete COMMIT and ReadyForQuery frames unchanged',async t=>{
 let n=0;const expected=Buffer.concat([frame('C','COMMIT\0'),frame('Z','I')]);
 const {proxy,bytes}=await scenario(t,s=>{if(++n===1)s.write(frame('Z','I'));else s.end(expected);},false);
 assert.deepEqual(bytes,expected);assert.equal(proxy.dropped,false);
});
test('armed proxy drops fragmented COMMIT and the coalesced ReadyForQuery acknowledgement',async t=>{
 let n=0;const complete=Buffer.concat([frame('C','COMMIT\0'),frame('Z','I')]);
 const {proxy,bytes}=await scenario(t,s=>{if(++n===1)s.write(frame('Z','I'));else{s.write(complete.subarray(0,3));setImmediate(()=>s.write(complete.subarray(3)));}},true);
 await proxy.waitForDrop();assert.equal(proxy.dropped,true);assert.equal(bytes.length,0);
});
test('COMMIT text in a non-command frame is not a commit acknowledgement',async t=>{
 let n=0;const expected=Buffer.concat([frame('N','COMMIT\0'),frame('C','SELECT 1\0'),frame('Z','I')]);
 const {proxy,bytes}=await scenario(t,s=>{if(++n===1)s.write(frame('Z','I'));else s.end(expected);},true);
 assert.deepEqual(bytes,expected);assert.equal(proxy.dropped,false);
});
for(const length of [3,9*1024*1024])test(`invalid backend frame length ${length} disconnects without forwarding a payload`,async t=>{
 let n=0;const header=Buffer.alloc(5);header[0]=67;header.writeUInt32BE(length,1);
 const {proxy,bytes}=await scenario(t,s=>{if(++n===1)s.write(frame('Z','I'));else s.write(header);},true);
 assert.equal(bytes.length,0);assert.equal(proxy.dropped,false);
});
