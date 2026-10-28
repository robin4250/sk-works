// Real PostgreSQL runner with synthetic auth. No production owner/challenge.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {generateKeyPairSync,sign} from 'node:crypto';
import assert from 'node:assert/strict';
import {readOwnMigrationKeyChallenge} from './key-migration-challenge-delivery.mjs';
import {checkChallengeHttpComposition} from './key-migration-challenge-http-check.mjs';
import {checkPasswordBoundChallenge} from './key-migration-challenge-issuer-password.mjs';
import {issueMigrationKeyChallenge} from './key-migration-challenge-issuer.mjs';
import {storeProvenPendingDeviceKey} from './key-migration-proven-adapter.mjs';
import {pendingDeviceKeyMigration} from './key-migration-proposal.mjs';
import {migrationPossessionPayload} from './key-migration-possession.mjs';
const require=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json');
const {Pool}=require('pg');
const pool=new Pool({max:4});
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const actor=id(1),session=id(2),deviceId=id(3);
const authenticatedPool={connect:async()=>{const client=await pool.connect();
 await client.query("select set_config('test.actor',$1,false),set_config('test.jwt',$2,false)",
 [actor,JSON.stringify({role:'authenticated',session_id:session,is_anonymous:false})]);return client;}};
try {
 for(const name of ['native-setup.sql','native-real-functions.sql','key-migration-registry.sql.review-only','key-migration-challenges.sql.review-only'])await pool.query(await readFile(new URL(name,import.meta.url),'utf8'));
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type)
 values ($1,$2,'unchanged-fixture-device','Synthetic iPhone','iphone')`,[deviceId,actor]);
 const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),publicKeyPem=pair.publicKey.export({type:'spki',format:'pem'}).toString();
 const args={pool:authenticatedPool,actor,session,deviceId,publicKeyPem};
 await assert.rejects(issueMigrationKeyChallenge({...args,actor:id(99)}));
 await assert.rejects(issueMigrationKeyChallenge({...args,session:id(99)}));
 await assert.rejects(issueMigrationKeyChallenge({...args,publicKeyPem:publicKeyPem+'extra'}));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges')).rows[0].count),0);
 const outcomes=await Promise.allSettled([issueMigrationKeyChallenge(args),issueMigrationKeyChallenge(args)]);
 assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
 const challenge=outcomes.find(x=>x.status==='fulfilled').value;
 assert.equal(challenge.actor,actor);assert.equal(challenge.session,session);assert.equal(challenge.expiresMs-challenge.createdMs,120000);
 assert.match(challenge.nonce,/^[a-f0-9]{64}$/);
 // Recover a lost issuance response without changing ID, nonce, expiry or row count.
 assert.deepEqual(await readOwnMigrationKeyChallenge(args),challenge);
 assert.deepEqual(await readOwnMigrationKeyChallenge(args),challenge);
 await assert.rejects(readOwnMigrationKeyChallenge({...args,actor:id(99)}));
 await assert.rejects(readOwnMigrationKeyChallenge({...args,session:id(99)}));
 const other=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString();
 await assert.rejects(readOwnMigrationKeyChallenge({...args,publicKeyPem:other}));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges')).rows[0].count),1);
 const proposal=pendingDeviceKeyMigration({actor,device:{id:deviceId,master_user_id:actor,is_locked:false,revoked_at:null},publicKeyPem});
 const signature=sign('sha256',migrationPossessionPayload(challenge,proposal),pair.privateKey);
 assert.equal((await storeProvenPendingDeviceKey({...args,challengeId:challenge.id,signature})).status,'pending');
 await assert.rejects(storeProvenPendingDeviceKey({...args,challengeId:challenge.id,signature}));
 await assert.rejects(readOwnMigrationKeyChallenge(args));
 // Consumed challenge permits an explicit new request, never an implicit retry.
 const next=await issueMigrationKeyChallenge(args);assert.notEqual(next.nonce,challenge.nonce);assert.notEqual(next.id,challenge.id);
 await pool.query('update private.master_devices set is_locked=true where id=$1',[deviceId]);
 await assert.rejects(issueMigrationKeyChallenge(args));
 await assert.rejects(readOwnMigrationKeyChallenge(args));
 await pool.query('update private.master_devices set is_locked=false where id=$1',[deviceId]);
 await pool.query('update master_device_enrollment_candidate.key_possession_challenges set created_ms=created_ms-240000,expires_ms=expires_ms-240000 where id=$1',[next.id]);
 await assert.rejects(readOwnMigrationKeyChallenge(args));
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'unchanged-fixture-device');
 await checkPasswordBoundChallenge({pool,authenticatedPool,actor,session,publicKeyPem});
 await checkChallengeHttpComposition({pool,authenticatedPool,actor,session,publicKeyPem});
 console.log('Internal challenge issuance: authenticated scope, canonical key, DB deadline, serialized one-active challenge, proof-to-pending, replay refusal, password failure-counter commit/lockout and unchanged legacy key passed. Synthetic auth only.');
} finally {await pool.end();}
