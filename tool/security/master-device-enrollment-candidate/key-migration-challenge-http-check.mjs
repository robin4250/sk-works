// Isolated HTTP-boundary composition with the real internal SQL issuer/readback.
// Auth transport is a fixture; this does not verify an actual HTTP bearer/JWT.
import assert from 'node:assert/strict';
import {handleMigrationChallengeRequest} from './key-migration-challenge-http-candidate.mjs';
export async function checkChallengeHttpComposition({pool,authenticatedPool,actor,session,publicKeyPem}) {
 const deviceId='00000000-0000-0000-0000-000000000009';
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type)
 values ($1,$2,'unchanged-http-fixture','Synthetic Mac','mac')`,[deviceId,actor]);
 const invoke=async body=>handleMigrationChallengeRequest(new Request('https://fixture.invalid/challenge',{
  method:'POST',headers:{authorization:'Bearer synthetic-verified-fixture-token','content-type':'application/json'},body:JSON.stringify(body)}),
  {authenticateBearer:async()=>({actor,session,pool:authenticatedPool})});
 const wrong=await invoke({action:'issue',deviceId,publicKeyPem,secondPassword:'synthetic-wrong'});
 assert.equal(wrong.status,403);assert.deepEqual(await wrong.json(),{accepted:false});
 assert.equal((await pool.query('select failed_attempts from public.user_secondary_credentials where user_id=$1',[actor])).rows[0].failed_attempts,1);
 const issued=await invoke({action:'issue',deviceId,publicKeyPem,secondPassword:'synthetic-correct'});
 assert.equal(issued.status,200);const original=await issued.json();assert.equal(original.accepted,true);
 const read=await invoke({action:'read',deviceId,publicKeyPem});assert.equal(read.status,200);
 assert.deepEqual(await read.json(),original,'readback cannot replace nonce, id, expiry or identity');
 const duplicate=await invoke({action:'issue',deviceId,publicKeyPem,secondPassword:'synthetic-correct'});
 assert.equal(duplicate.status,409);assert.ok(!(await duplicate.text()).includes('synthetic-correct'));
 assert.equal(Number((await pool.query('select count(*) from master_device_enrollment_candidate.key_possession_challenges where device_id=$1',[deviceId])).rows[0].count),1);
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'unchanged-http-fixture');
}
