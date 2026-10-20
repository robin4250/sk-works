// Dedicated readiness action on the existing disposable fixture, never production.
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
let script = await fs.readFile(new URL('./verify_qualification_admin_saved_photos.mjs', import.meta.url), 'utf8');
const readAnchor = "const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');";
if (script.split(readAnchor).length !== 2) throw new Error('fixture read anchor changed');
script = script.replace(readAnchor, `const read=p=>fs.readFile(${JSON.stringify(root)}+p,'utf8');`);
const baselineVerifier = await fs.readFile(new URL('./verify_qualification_admin_photo_baseline.mjs', import.meta.url), 'utf8');
const baselineCheck = baselineVerifier.match(/const check = `([\s\S]*?)`;\nscript = script\.replace/);
if (!baselineCheck) throw new Error('baseline verifier anchor changed');
const marker = ' // Exact original source drift failed before candidate DDL, checked above.';
if (script.split(marker).length !== 2) throw new Error('fixture test anchor changed');
const before = `
 await owner();await db.exec("set test.active='true'");
 const readinessPatch=await read('docs/candidates/qualification_admin_photo_prepare_readiness_20261021.sql.review-only');
 await assert.rejects(db.exec(readinessPatch),e=>e.code==='55000');await db.exec('rollback');
 await actor(admin);
 await assert.rejects(rpc('admin_saved_photo_prepare_readiness',{company_id:company}));
 const legacyPersonalReadinessBefore=await rpc('photo_capability');
 const legacyAdminReadinessBefore=await rpc('admin_saved_photo_capability',{company_id:company});
`;
const after = `
 await owner();
 const readinessMetadataSql="select oid::text,proowner::text,proacl::text,prosecdef,proconfig from pg_proc where oid in ('private.admin_qualification_saved_photos(text,jsonb)'::regprocedure,'private.personal_qualification_submission(text,jsonb)'::regprocedure) order by oid";
 const readinessMetadataBefore=(await db.query(readinessMetadataSql)).rows;
 const readState=async()=>({
  qualifications:(await db.query('select to_jsonb(q) v from worker_qualifications q order by id')).rows,
  requests:(await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,
  storage:(await db.query('select to_jsonb(o) v from storage.objects o order by name')).rows,
 });
 const readinessStateBefore=await readState();
 await db.exec(readinessPatch);
 assert.deepEqual((await db.query(readinessMetadataSql)).rows,readinessMetadataBefore);
 assert.deepEqual(await readState(),readinessStateBefore);
 await actor(admin);
 const readinessExpected={version:1,contract:'qualification_admin_photo_prepare_baseline',company_id:company,actor_id:admin,
 baseline_guard_version:1,prepare_action:'prepare_admin_saved_photos',photo_submission_available:true,
 photo_upload_allowed:false,max_photos:20,self_approval_allowed:false};
 assert.deepEqual(await rpc('admin_saved_photo_prepare_readiness',{company_id:company}),readinessExpected);
 assert.deepEqual(await rpc('photo_capability'),legacyPersonalReadinessBefore);
 assert.deepEqual(await rpc('admin_saved_photo_capability',{company_id:company}),legacyAdminReadinessBefore);
 await db.exec("set test.manage_people='false'");
 assert.deepEqual(await rpc('admin_saved_photo_prepare_readiness',{company_id:company}),{...readinessExpected,photo_submission_available:false});
 await db.exec("set test.manage_people='true'");
 for(const denied of [user,foreignUser]){
  await actor(denied);
  const read=await rpc('admin_saved_photo_prepare_readiness',{company_id:company});
  assert.equal(read.actor_id,denied);assert.equal(read.photo_submission_available,false);
 }
 await actor(admin);
 await assert.rejects(rpc('admin_saved_photo_prepare_readiness',{}),e=>e.code==='22023');
 await assert.rejects(rpc('admin_saved_photo_prepare_readiness',{company_id:'bad'}),e=>e.code==='22P02');
 for(const flag of ['false','']){
  if(flag===''){
   await owner();await db.exec('create or replace function private.account_access_allowed() returns boolean language sql stable as $$select null::boolean$$');await actor(admin);
  }else await db.exec("set test.active='false'");
  await assert.rejects(rpc('admin_saved_photo_prepare_readiness',{company_id:company}),e=>e.code==='42501');
 }
 await owner();await db.exec("create or replace function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('test.active',true),'true')='true'$$;set test.active='true'");
 await actor(admin);
 await assert.rejects(rpc('prepare_admin_saved_photos',baselineData(45,['unseen'])),e=>e.code==='40001');
 await owner();assert.deepEqual(await readState(),readinessStateBefore);
 await assert.rejects(db.exec(readinessPatch),e=>e.code==='55000');await db.exec('rollback');
 console.log('PASS prepare readiness: missing baseline refuses installation, old server missing action OFF, exact dedicated read response, legacy responses unchanged, current permission/account checks, no row mutation, baseline still enforced, metadata and unknown-source guard');
`;
script = script.replace(marker, () => before + '\n' + baselineCheck[1] + '\n' + after + '\n' + marker);
await import('data:text/javascript;base64,' + Buffer.from(script).toString('base64'));
