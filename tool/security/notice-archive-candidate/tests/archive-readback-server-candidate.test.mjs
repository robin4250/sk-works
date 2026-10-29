import {test} from 'node:test';import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {createArchiveReadbackServerCandidate} from '../src/archive-readback-server-candidate.mjs';
import {serverFixture} from './archive-readback-server-fixture.mjs';

test('OFF TLS server composes existing caller/session/company guard with immutable descriptor registry',{timeout:60000},async t=>{
 const f=await serverFixture(t),s=await f.start(),input=d=>({authority_id:f.authority,challenge:'a'.repeat(64),descriptor:d});
 await t.test('default OFF cannot construct a listener or call a port',()=>{
  let called=0;assert.throws(()=>createArchiveReadbackServerCandidate({pool:{connect(){called++;}},store:{restore(){called++;}}}));assert.equal(called,0);
 });
 await t.test('real TLS client/server Auth transport and existing SQL guards return only a signed own observation',async()=>{
  const result=await s.client().verify(f.own);assert.equal(result.status,'readback_verified_unattested');assert.deepEqual(result.receipt.payload.descriptor,f.own);
  assert.deepEqual(f.counts(),{acquisitions:1,restores:1,signatures:1});
  assert.equal(f.authCalls[0].url,'https://auth-fixture.invalid/auth/v1/user');assert.equal(f.authCalls[0].headers.apikey,'fixture-public-key');
  assert.equal(f.queries.filter(q=>q.includes('archive_readback_private.authorize_observation')).length,2);
  assert.deepEqual(await f.clean(),{actor:null,jwt:null});assert.equal(f.releases.at(-1),false);
 });
 await t.test('cross-company, changed descriptor and stored-but-unregistered bytes refuse before restore/sign',async()=>{
  const before=f.counts();await assert.rejects(s.client().verify(f.foreign));
  await assert.rejects(s.client().verify({...f.foreign,company_id:f.company}));
  await assert.rejects(s.client().verify({...f.own,snapshot_sha256:'b'.repeat(64)}));
  const bytes=Buffer.from('unregistered local fixture'),{createHash}=await import('node:crypto');
  const d=await f.store.retain({company_id:f.company,event_id:f.own.event_id,revision:3,snapshot_sha256:'c'.repeat(64),payload_sha256:createHash('sha256').update(bytes).digest('hex'),payload:bytes});
  await assert.rejects(s.client().verify(d));assert.equal(f.counts().restores,before.restores);assert.equal(f.counts().signatures,before.signatures);
  assert.equal((await f.db.query('select count(*)::int n from archive_readback_private.authority_records')).rows[0].n,2);
  assert.deepEqual(await f.clean(),{actor:null,jwt:null});
 });
 await t.test('forged JWT/role and body actor/pool/metadata cannot supply authority',async()=>{
  const before=f.counts(),valid=f.token(),parts=valid.split('.');
  const forged=`${parts[0]}.${Buffer.from(JSON.stringify({sub:f.other,session_id:f.sid,role:'authenticated',exp:4102444800,iat:1})).toString('base64url')}.${parts[2]}`;
  await assert.rejects(s.client(forged).verify(f.own));await assert.rejects(s.client(f.token({role:'service_role'})).verify(f.own));
  assert.equal(f.counts().acquisitions,before.acquisitions);
  for(const extra of [{actor:f.actor},{pool:{}},{user_metadata:{master:true}},{register:true}])assert.equal((await s.raw({...input(f.own),...extra})).status,503);
  assert.equal(f.counts().restores,before.restores);assert.equal(f.counts().signatures,before.signatures);
 });
 await t.test('live Master/company/session/credential/deployment/account checks are actual existing SQL',async()=>{
  const mutations=[
   ["update private.master_admins set enabled=false where user_id=$1","update private.master_admins set enabled=true where user_id=$1"],
   ["update company_members set role='employee'where user_id=$1","update company_members set role='owner'where user_id=$1"],
   ["update auth.sessions set not_after=clock_timestamp()-interval '1 second'where user_id=$1","update auth.sessions set not_after=null where user_id=$1"],
   ["update user_secondary_credentials set locked_until=clock_timestamp()+interval '1 hour'where user_id=$1","update user_secondary_credentials set locked_until=null where user_id=$1"],
   ["update security_management_issuer_private.deployments set enabled=false where owner_id=$1","update security_management_issuer_private.deployments set enabled=true where owner_id=$1"],
   ["update auth.users set banned_until=clock_timestamp()+interval '1 hour'where id=$1","update auth.users set banned_until=null where id=$1"],
  ];
  for(const [deny,restore]of mutations){const before=f.counts();await f.db.query(deny,[f.actor]);
   await assert.rejects(s.client(f.token({metadata:{is_master:true,company_id:f.company}})).verify(f.own));
   assert.equal(f.counts().restores,before.restores);assert.equal(f.counts().signatures,before.signatures);await f.clean();await f.db.query(restore,[f.actor]);
  }
  const before=f.counts();await f.db.query('delete from auth.sessions where id=$1',[f.sid]);await assert.rejects(s.client().verify(f.own));
  assert.equal(f.counts().restores,before.restores);await f.clean();await f.db.query('insert into auth.sessions values($1,$2,null)',[f.sid,f.actor]);
 });
 await t.test('immutable saved target cannot be rewritten or read by client roles',async()=>{
  for(const q of ["update archive_readback_private.authority_records set revision=3","delete from archive_readback_private.authority_records","truncate archive_readback_private.authority_records"])await assert.rejects(f.db.query(q),e=>e.code==='55000');
  for(const role of ['anon','authenticated','service_role']){await f.db.exec(`begin;set local role ${role}`);await assert.rejects(f.db.query('select * from archive_readback_private.authority_records'),e=>e.code==='42501');await f.db.exec('rollback');}
 });
 await t.test('runtime role can use only narrow helper and cannot acquire raw source or guard privileges',async()=>{
  await f.db.exec('begin;set local role archive_readback_runtime');
  await assert.rejects(f.db.query('select * from archive_readback_private.authority_records'),e=>e.code==='42501');await f.db.exec('rollback');
  for(const role of ['anon','authenticated','service_role'])assert.equal((await f.db.query("select has_function_privilege($1,'archive_readback_private.authorize_observation(uuid,jsonb)','execute') allowed",[role])).rows[0].allowed,false);
  await f.db.exec('begin');
  await f.db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:f.actor,session_id:f.sid,role:'authenticated',is_anonymous:false})]);
  await f.db.exec('set local role archive_readback_runtime');
  const result=(await f.db.query('select archive_readback_private.authorize_observation($1,$2::jsonb) as observation',[f.authority,JSON.stringify(f.own)])).rows[0].observation;
  assert.deepEqual(Object.keys(result).sort(),['descriptor','guard_token']);assert.deepEqual(result.descriptor,f.own);assert.match(result.guard_token,/^[a-f0-9]{64}$/);
  await f.db.exec('rollback');
 });
 await t.test('session expiry after restore/sign is rechecked before commit and receipt delivery',async()=>{
  const before=f.counts(),changing=await f.start({store:{async restore(d){const bytes=await f.store.restore(d);await f.db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=$1",[f.sid]);return bytes;}}});
  await assert.rejects(changing.client().verify(f.own));assert.equal(f.counts().signatures,before.signatures+1);
  // The isolated fixture mutates within the same transaction only to test the
  // final clock recheck. Real concurrent-update blocking needs Native PG tests.
  await f.clean();assert.equal((await f.db.query('select not_after from auth.sessions where id=$1',[f.sid])).rows[0].not_after,null);
 });
 await t.test('synchronous signer overrun cannot bypass monotonic deadline while timer callback is starved',{timeout:10000},async sub=>{
  const monotonic=performance.now.bind(performance);let clock=0,signs=0;
  sub.mock.method(performance,'now',()=>clock);sub.mock.timers.enable({apis:['setTimeout']});
  const busy=await f.start({timeoutMs:50,signObservation:async bytes=>{
   signs++;const began=monotonic();while(monotonic()-began<60){}clock=51;
   return f.signBytes(bytes); // Valid signature must still be rejected as late.
  }});
  const queries=f.queries.length;await assert.rejects(busy.client().verify(f.own));assert.equal(signs,1);
  assert.equal(f.queries.slice(queries).filter(q=>q.includes('archive_readback_private.authorize_observation')).length,1);
  assert.equal(f.queries.slice(queries).includes('commit'),false);sub.mock.restoreAll();sub.mock.timers.reset();
  await f.clean();assert.equal(f.releases.at(-1),true);
 });
 await t.test('a synchronously late pool lease is discarded before BEGIN',{timeout:10000},async sub=>{
  const monotonic=performance.now.bind(performance);let clock=0;
  sub.mock.method(performance,'now',()=>clock);sub.mock.timers.enable({apis:['setTimeout']});
  const late=await f.start({timeoutMs:50,pool:{async connect(){
   const client=await f.pool.connect(),began=monotonic();while(monotonic()-began<60){}clock=51;return client;
  }}});
  const before=f.queries.length;await assert.rejects(late.client().verify(f.own));
  assert.equal(f.queries.length,before);assert.equal(f.releases.at(-1),true);
  sub.mock.restoreAll();sub.mock.timers.reset();await f.clean();
 });
});
