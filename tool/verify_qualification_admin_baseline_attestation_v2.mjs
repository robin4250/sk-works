// Synthetic isolated fixture only. Reuse original SQL/fixture and old baseline tests.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
let script=await read('tool/verify_qualification_admin_saved_photos.mjs');
const baseline=await read('tool/verify_qualification_admin_photo_baseline.mjs');
const extracted=baseline.match(/const check = `([\s\S]*?)`;\nscript = script.replace/);
assert.ok(extracted&&!extracted[1].includes('${'),'literal baseline checks must remain reusable');
const oldRead="const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');";
assert.equal(script.split(oldRead).length,2);
script=script.replace(oldRead,()=>`const read=p=>fs.readFile(${JSON.stringify(root)}+p,'utf8');`);
const beforePatch=' await db.exec(patch);';
assert.equal(extracted[1].split(beforePatch).length,2);
const checks=extracted[1].replace(beforePatch,()=>beforePatch+`
 const attestation=await read('docs/candidates/qualification_admin_baseline_attestation_v2_20261031.sql.review-only');
 const beforeAttestation=(await db.query(metadataSql)).rows;
 await db.exec(attestation);
 assert.deepEqual((await db.query(metadataSql)).rows,beforeAttestation,'attestation preserves owner/ACL/OID/security');
 await actor(admin);
 const capability=await rpc('admin_saved_photo_capability',{company_id:company});
 assert.deepEqual(capability,{version:2,expected_photo_paths_required:true,
  contract:'qualification_admin_saved_photos',company_id:company,actor_id:admin,
  photo_submission_available:true,photo_upload_allowed:false,max_photos:20,self_approval_allowed:false});
 await assert.rejects(db.exec(attestation),e=>e.code==='55000');await db.exec('rollback');
`);
const marker=' // Exact original source drift failed before candidate DDL, checked above.';
assert.equal(script.split(marker).length,2);
script=script.replace(marker,()=>checks+'\n'+marker);
await import('data:text/javascript;base64,'+Buffer.from(script).toString('base64'));
