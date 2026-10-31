// Fixture-only executable composition of the unchanged administrator candidate.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import{createHash}from'node:crypto';import{spawnSync}from'node:child_process';import{pathToFileURL}from'node:url';
const candidateRoot=path.resolve(process.env.SKO_DOCUMENT_ADMIN_CANDIDATE_SOURCE??'.');
const base=path.join(candidateRoot,'docs/review/worker-document-admin-self-correction/verify.mjs');
const source=await fs.readFile(base,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='fffeafadb38ae674d5a3e6c0d65c6a0570f091144b6d0c947784ce972cf04e9a')throw Error('pinned fixture source changed');
const directory=path.dirname(new URL(import.meta.url).pathname);
const needle=" await db.exec(await fs.readFile(new URL('../../candidates/worker_document_admin_self_correction_20261031.sql.review-only',import.meta.url),'utf8'));";
if(source.split(needle).length!==2)throw Error('exact candidate installation anchor changed');
const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'sko-admin-guard-fixture-'));
const generated=path.join(path.dirname(base),'.guarded-execution.generated.mjs');
const injection=`
 const deploymentDirectory=${JSON.stringify(directory)};
 const captureQuery=(await fs.readFile(path.join(deploymentDirectory,'catalog.sql'),'utf8')).trim().replace(/;$/,'');
 const capture=(await db.query("select q.snapshot,encode(sha256(convert_to(q.snapshot::text,'UTF8')),'hex') snapshot_sha256 from("+captureQuery+")q")).rows[0];
 const inputPath=${JSON.stringify(path.join(tmp,'before.json'))};
 await fs.writeFile(inputPath,JSON.stringify(capture));
 const output=${JSON.stringify(path.join(tmp,'proposal'))};
 const prepared=spawnSync('python3',[path.join(deploymentDirectory,'prepare.py'),'--before',inputPath,'--catalog',path.join(deploymentDirectory,'catalog.sql'),'--candidate',path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../candidates/worker_document_admin_self_correction_20261031.sql.review-only'),'--output',output],{encoding:'utf8'});
 assert.equal(prepared.status,0,prepared.stderr);
 const install=await fs.readFile(path.join(output,'install-off.guarded.sql.review-only'),'utf8');
 const restore=await fs.readFile(path.join(output,'restore-unused.guarded.sql.review-only'),'utf8');
 const enable=await fs.readFile(path.join(output,'enable-separately-approved.guarded.sql.review-only'),'utf8');
 await db.exec(install);assert.deepEqual(await status(),original);
 assert.equal((await db.query('select enabled from private.worker_document_admin_correction_state')).rows[0].enabled,false);
 await db.exec(restore);assert.equal((await db.query("select to_regprocedure('public.worker_document_admin_self_correction(text,jsonb)') v")).rows[0].v,null);
 await db.exec(install);assert.deepEqual(await status(),original);
 await db.exec('alter function private.worker_document_photos_are_retained(text) volatile');
 await assert.rejects(db.exec(enable));await db.exec('rollback');
 assert.equal((await db.query('select enabled from private.worker_document_admin_correction_state')).rows[0].enabled,false);
 await db.exec('alter function private.worker_document_photos_are_retained(text) stable');
 await db.exec(enable);assert.deepEqual(await status(),original);
 assert.equal((await db.query('select enabled from private.worker_document_admin_correction_state')).rows[0].enabled,true);
 await db.exec('update private.worker_document_admin_correction_state set enabled=false');
 await assert.rejects(db.exec(restore));await db.exec('rollback');
 assert.equal((await db.query('select enabled from private.worker_document_admin_correction_state')).rows[0].enabled,false);
 assert.deepEqual(await status(),original);
 console.log('GUARD PASS: OFF/install-originals/unused-restore/reinstall/dependency-drift-ON-stop/ON-originals/ever-activated-restore-stop');
`;
// This fixture only replaces direct installation with the generated guarded
// capsule. Candidate SQL and the rest of the 18 Native checks remain unchanged.
const transformed=source.replace(needle,injection).replace("import fs from 'node:fs/promises';", "import fs from 'node:fs/promises';import{spawnSync}from'node:child_process';import{fileURLToPath}from'node:url';");
await fs.writeFile(generated,transformed,{flag:'wx'});
try{await import(pathToFileURL(generated));}finally{await fs.rm(generated);await fs.rm(tmp,{recursive:true,force:true});}
