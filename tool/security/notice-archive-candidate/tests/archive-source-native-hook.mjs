// Called only inside the pinned, disposable #1494 Native PG17 fixture.
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomBytes,randomUUID,createCipheriv,createDecipheriv} from 'node:crypto';
import {createArchiveByteStoreCandidate} from '../src/archive-byte-store-candidate.mjs';
export async function verifyLockedSourceExport({db,a,b,claims,actor,sid,cid,collector,event,sha}){
 const read=p=>readFile(new URL(p,import.meta.url),'utf8');
 const management=await read('../../free-worker-candidate/issuer/management-issuer.sql.review-only');
 // Exact existing deployment table/binding/digest source; Auth surroundings are
 // inherited synthetic fixtures, not a live deployment or a substitute verifier.
 await db.query('alter table auth.users add column deleted_at timestamptz;create schema security_management_issuer_private');
 await db.query(management.match(/create table security_management_issuer_private\.deployments\([\s\S]*?\n\);/)[0]);
 await db.query(management.match(/create function security_management_issuer_private\.digest\([\s\S]*?\$\$;/)[0]);
 await db.query(management.match(/create function security_management_issuer_private\.binding\([\s\S]*?end \$binding\$;/)[0]);
 const jwk={kty:'OKP',crv:'Ed25519',x:'A'.repeat(43)};
 await db.query('insert into public.user_secondary_credentials(user_id,password_hash)values($1,$2)',[actor,'synthetic fixture credential']);
 await db.query('insert into security_management_issuer_private.deployments(deployment_id,company_id,owner_id,enabled,key_id,key_version,manager_jwk)values($1,$2,$3,true,$4,1,$5)',
  ['deployment',cid,actor,'fixture',jwk]);
 await db.query(await read('../src/archive-readback-registry.sql.review-only'));
 await db.query(await read('../src/archive-source-export.sql.review-only'));
 await db.query(await read('../src/archive-source-register.sql.review-only'));
 // Normalize the race winner by using the real canonical proof/review writer.
 let current=(await db.query('select revision,review_state from security_observation_notice_private.inbox where event_id=$1',[event.event_id])).rows[0];
 if(current.review_state!=='resolved'){
  const proof=randomBytes(32).toString('hex');await claims(db,'service_role');
  await db.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[actor,sid,'master.security_collector.read',{scope:'decoy_collector'},sha(proof)]);
  await claims(db,'authenticated');await db.query('select public.update_security_observation_notice($1,$2,$3,$4,$5,$6)',[event.event_id,'resolved','reviewed fixture',current.revision,randomUUID(),proof]);
 }
 current=(await db.query('select revision from security_observation_notice_private.inbox where event_id=$1',[event.event_id])).rows[0];
 await claims(db,'authenticated');await claims(a,'authenticated');await claims(b,'authenticated');
 const exportSource=c=>c.query('select archive_readback_private.lock_source_export($1,$2,$3) s',[event.event_id,current.revision,'deployment']);
 const authority=randomUUID(),directory=await mkdtemp(join(tmpdir(),'sko-source-export-'));
 let checks=0;
 try{
  const store=await createArchiveByteStoreCandidate({enabled:true,directory});
  await a.query('begin');const exported=(await exportSource(a)).rows[0].s;
  assert.equal(sha(exported.snapshot_body),exported.snapshot_sha256);checks++;
  assert.equal(JSON.parse(exported.snapshot_body).source_envelope.body_base64.length>0,true);
  assert.equal(exported.snapshot_body.includes('synthetic fixture credential'),false);checks++;
  // Actual encrypted full bytes + decrypt/compare + store/readback. This uses
  // synthetic local AES material, not genuine independent KMS/custody.
  const key=randomBytes(32),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
  const encrypted=Buffer.concat([cipher.update(exported.snapshot_body,'utf8'),cipher.final()]);
  const payload=Buffer.concat([iv,cipher.getAuthTag(),encrypted]);
  const descriptor=await store.retain({company_id:cid,event_id:event.event_id,revision:Number(current.revision),snapshot_sha256:exported.snapshot_sha256,payload_sha256:sha(payload),payload});
  const restored=await store.restore(descriptor),dec=createDecipheriv('aes-256-gcm',key,restored.subarray(0,12));dec.setAuthTag(restored.subarray(12,28));
  assert.equal(Buffer.concat([dec.update(restored.subarray(28)),dec.final()]).toString('utf8'),exported.snapshot_body);checks++;
  const register=c=>c.query('select archive_readback_private.register_locked_source($1,$2,$3,$4,$5,$6,$7) r',
   [event.event_id,current.revision,'deployment',authority,exported.snapshot_sha256,payload,descriptor.object_id]);
  const first=(await register(a)).rows[0].r;assert.deepEqual(first.descriptor,descriptor);checks++;
  assert.deepEqual((await register(a)).rows[0].r,first);checks++;
  // The source and current inbox are still protected through registration.
  await b.query("set lock_timeout='100ms'");
  await assert.rejects(b.query('update security_observation_notice_private.inbox set revision=revision+1 where event_id=$1',[event.event_id]),e=>e.code==='55P03');checks++;
  await a.query('rollback');
  assert.equal((await db.query('select count(*)::int n from archive_readback_private.authority_records')).rows[0].n,0);checks++;
  // Published encrypted bytes remain; a DB rollback never deletes originals.
  assert.deepEqual(await store.restore(descriptor),payload);checks++;
  await a.query('begin');await register(a);await a.query('commit');
  assert.deepEqual((await register(db)).rows[0].r,first);checks++;
  for(const role of ['anon','authenticated','service_role']){
   await db.query('set role '+role);await assert.rejects(register(db));await db.query('reset role');checks++;
  }
  const mutate=async(sql,args=[])=>{await db.query('begin');try{await db.query(sql,args);await assert.rejects(register(db));checks++;}finally{await db.query('rollback');}};
  await mutate('update security_observation_notice_private.config set enabled=false');
  await mutate('update security_management_issuer_private.deployments set enabled=false');
  await mutate('update public.company_members set role=$1',['worker']);
  await mutate('delete from auth.sessions where id=$1',[sid]);
  await mutate('update private.security_collector_evidence set original_body=$1 where event_id=$2',[Buffer.from('tampered'),event.event_id]);
  await mutate('delete from security_observation_notice_private.audit where event_id=$1 and action=$2',[event.event_id,'queued']);
  await assert.rejects(db.query('update archive_readback_private.authority_records set byte_length=1'));checks++;
  assert.equal((await db.query('select count(*)::int n from private.security_collector_evidence where event_id=$1',[event.event_id])).rows[0].n,1);checks++;
  console.log(JSON.stringify({result:'PASS Native PG17 actual #1494 source/export/register composition',checks,actual_collector_hmac:true,actual_notice_revision_writer:true,synthetic_auth_surroundings:true,real_gotrue:false,kms_or_independent_custody:false,production_changed:false,source_released:false}));
 }finally{await a.query('rollback').catch(()=>{});await db.query('rollback').catch(()=>{});await rm(directory,{recursive:true,force:true});}
}
