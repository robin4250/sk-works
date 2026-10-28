import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createScannerRegistrationChallengeAdapter} from './qr-scanner-challenge-adapter.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const target={companyId:id(1),deviceId:id(2),keyHex:'302a300506032b6570032100'+'ab'.repeat(32)};
function fixture(options={}) {
 const calls=[],value={id:id(3),company:target.companyId,actor:id(4),session:id(5),device:target.deviceId,keyHex:target.keyHex,nonce:id(6),createdMs:100,expiresMs:90100,databaseNowMs:200,...options.change};
 const client={async query(sql,args){calls.push({sql,args});
  if(sql.includes('issue_scanner'))return {rows:[{id:id(3)}]};
  if(sql.includes('load_scanner')||sql.includes('read_own'))return {rows:[{challenge:options.empty?null:value}]};
  if(sql==='commit'){if(options.mutate)value.device=id(99);if(options.commitError)throw Error('private db information');}return {rows:[]};},release(discard){calls.push({sql:'release',discard});}};
 return {calls,adapter:createScannerRegistrationChallengeAdapter({pool:{connect:async()=>client},initializeVerifiedSession:async()=>({actor:id(4),session:id(5)})})};
}
test('challenge is returned only after commit and independent of adapter-owned mutation',async()=>{
 const f=fixture({mutate:true});const result=await f.adapter.issue(target);assert.equal(result.device,target.deviceId);
 assert.equal(f.calls.at(-2).sql,'commit');await assert.rejects(f.adapter.issue(target));
 assert.equal(f.calls.filter(x=>x.sql.includes('issue_scanner')).length,1);
});
test('read never issues or extends missing challenge',async()=>{
 const f=fixture({empty:true});assert.equal(await f.adapter.read(target),null);
 assert.equal(f.calls.filter(x=>x.sql.includes('issue_scanner')).length,0);assert.equal(f.calls.at(-2).sql,'commit');
});
test('scope, principal, time and malformed result rejected without commit',async()=>{
 for(const change of [{company:id(99)},{device:id(99)},{actor:id(99)},{session:id(99)},{keyHex:target.keyHex.slice(0,-2)+'cd'},{databaseNowMs:90100},{databaseNowMs:99},{expiresMs:90101}]){
  const f=fixture({change});await assert.rejects(f.adapter.issue(target));assert.ok(f.calls.some(x=>x.sql==='rollback'));assert.ok(!f.calls.some(x=>x.sql==='commit'));
 }
});
test('unknown commit does not expose result, secrets, or permit automatic resend',async()=>{
 const f=fixture({commitError:true});await assert.rejects(f.adapter.issue(target),e=>!e.message.includes('private db'));
 await assert.rejects(f.adapter.issue(target));assert.equal(f.calls.filter(x=>x.sql.includes('issue_scanner')).length,1);
});
