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
const withLegacy=process.env.SKO_DOCUMENT_ADMIN_WITH_LEGACY==='1';
const legacyInstall=withLegacy?`
 const legacyCandidate=await read('docs/candidates/worker_document_change_session_20261029/install.sql.review-only');
 assert.equal(createHash('sha256').update(legacyCandidate).digest('hex'),'1f078c9a60e8c19163e7656a5067dec8ae9e20e0703cbd06073069c9e6f830ca');
 await db.exec(legacyCandidate);
 // Match the already-reviewed OFF deployment's new-wrapper narrowing only.
 await db.exec('revoke all on function public.worker_document_change(text,jsonb) from service_role');
 await db.exec('update private.worker_document_change_installation set catalog=private.worker_document_change_catalog() where singleton');
 await db.exec('update private.worker_document_change_rollout set enabled=true');
 console.log('Legacy actual candidate/guard installed and ON only in disposable fixture');
`:'';
const additionalPhotos=`
 const secondPhoto=photo.replace('old.png','second.png');
 await db.query('insert into storage.objects(bucket_id,name) values($1,$2)',['worker-documents',secondPhoto]);
 await db.query('update public.worker_document_statuses set attachment_paths=$1 where id=$2',[[photo,secondPhoto],target]);
`;
const retainedChecks=`
 await db.exec('reset role');
 for(const retainedPath of original.attachment_paths){
  assert.equal((await db.query('select exists(select 1 from public.worker_document_status_history where $1=any(attachment_paths)) v',[retainedPath])).rows[0].v,true);
 }
 await actor(owner,uid(30));
 for(const retainedPath of original.attachment_paths){
  assert.equal((await db.query('select private.worker_document_photos_are_retained($1) v',[retainedPath])).rows[0].v,true);
  assert.deepEqual((await db.query('delete from storage.objects where bucket_id=$1 and name=$2 returning id',['worker-documents',retainedPath])).rows,[]);
  assert.deepEqual((await db.query('update storage.objects set name=name||$1 where bucket_id=$2 and name=$3 returning id',['.overwrite','worker-documents',retainedPath])).rows,[]);
 }
 const retentionMetadata=(await db.query("select p.oid::regprocedure::text signature,md5(pg_get_functiondef(p.oid)) definition_md5,md5(p.prosrc) source_md5 from pg_proc p where p.oid in(to_regprocedure('private.normalize_worker_document_photos()'),to_regprocedure('private.capture_worker_document_photo_baseline()'),to_regprocedure('public.capture_worker_document_status_history()'),to_regprocedure('private.worker_document_photos_are_retained(text)')) order by signature")).rows;
 console.log('RETENTION METADATA '+JSON.stringify(retentionMetadata));
 console.log('RETENTION PASS: both originals including removed photo reach real baseline history/helper and restrictive authenticated DELETE/UPDATE policies; real Storage/cleanup not exercised');
`;
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
let transformed=source.replace(needle,injection).replace(" const original=await status();",legacyInstall+additionalPhotos+" const original=await status();").replace(" console.log(JSON.stringify({checks:count",retainedChecks+" console.log(JSON.stringify({checks:count");
if(withLegacy){
 transformed=transformed.replace("await db.exec('create table private.worker_document_changes(target_id uuid,status text)');",'');
 transformed=transformed.replace('await db.query("insert into private.worker_document_changes values($1,\'pending\')",[target]);', `await db.query("insert into private.worker_document_changes(id,company_id,worker_id,requirement_id,target_id,requested_by,created_session_id,status,previous,proposed) values($1,$2,$3,$4,$5,$6,$7,'pending',$8::jsonb,$8::jsonb)",[uid(99),company,worker,req,target,owner,sid,JSON.stringify(original)]);`);
}
transformed=transformed.replace("import fs from 'node:fs/promises';", "import fs from 'node:fs/promises';import{spawnSync}from'node:child_process';import{fileURLToPath}from'node:url';import{createHash}from'node:crypto';");
await fs.writeFile(generated,transformed,{flag:'wx'});
try{await import(pathToFileURL(generated));}finally{await fs.rm(generated);await fs.rm(tmp,{recursive:true,force:true});}
