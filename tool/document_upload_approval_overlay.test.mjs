import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const { PGlite } = await import(pathToFileURL(resolve(process.env.SKO_PGLITE_MODULE ?? 'tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js')));
const { setupWorkerDocumentChangeFixture,uid,company,worker,requirement,owner,reviewer,outsider,target,photo } = await import(pathToFileURL(resolve(process.env.SKO_DOCUMENT_FIXTURE ?? 'tool/worker_document_change_live_session_fixture.mjs')));
const db=new PGlite();
const actor=async id=>{await db.exec('reset role');await db.query("select set_config('fixture.uid',$1,false)",[id]);await db.exec('set role authenticated');};
const rpc=async(a,d)=>(await db.query('select public.worker_document_change($1,$2::jsonb) value',[a,JSON.stringify(d)])).rows[0].value;
try {
 await setupWorkerDocumentChangeFixture(db);
 await db.exec("select set_config('fixture.session','live',false); alter table storage.objects add column version text, add column is_delete_marker boolean not null default false");
 await db.exec(await readFile(new URL('./document_upload_inspection.sql.review-only',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('./document_upload_approval_overlay.sql.review-only',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('./document_upload_commit_boundary.sql.review-only',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('./document_upload_draft_finalize.sql.review-only',import.meta.url),'utf8'));
 await actor(owner);
 await db.exec(`insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,updated_by) values('${target}','${company}','${worker}','${requirement}','${owner}')`);
 await db.exec(`update public.worker_document_statuses set status='submitted',attachment_path='${photo}',notes='original',updated_by='${owner}' where id='${target}'`);
 const stamp=(await db.query(`select updated_at from public.worker_document_statuses where id='${target}'`)).rows[0].updated_at;
 const id=uid(40), path=`${company}/${worker}/${requirement}/${id}/new.pdf`;
 await db.exec('reset role');
 await db.exec(`insert into storage.objects(bucket_id,name,version) values('worker-documents','${path}','v1');
 insert into private.document_upload_inspection_candidates(id,actor_id,company_id,worker_id,requirement_id,request_id,object_path,object_version,status,sha256,byte_count,mime,expires_at)
 values('${uid(50)}','${owner}','${company}','${worker}','${requirement}','${id}','${path}','v1','inspected','${'a'.repeat(64)}',16,'application/pdf',clock_timestamp()+interval '2 minutes')`);
 const command={request_id:id,status_id:target,expected_updated_at:stamp,proposed:{attachment_paths:[path],notes:'updated',expires_at:null}};
 await actor(owner);await assert.rejects(rpc('prepare',command));
 await db.exec('reset role');await db.exec('update private.document_change_upload_rollout set enabled=true');
 await actor(outsider);await assert.rejects(rpc('prepare',command));
 await actor(owner);assert.equal((await rpc('prepare',command)).status,'draft');await rpc('submit',{request_id:id});await assert.rejects(rpc('approve',{request_id:id}));
 await db.exec('reset role');await db.exec('update private.document_change_upload_rollout set enabled=false');await actor(reviewer);await assert.rejects(rpc('approve',{request_id:id}));
 await db.exec('reset role');await db.exec('update private.document_change_upload_rollout set enabled=true');await db.exec(`update storage.objects set version='v2' where name='${path}'`);await actor(reviewer);await assert.rejects(rpc('approve',{request_id:id}));
 await db.exec('reset role');await db.exec(`update storage.objects set version='v1' where name='${path}'`);await actor(reviewer);assert.equal((await rpc('approve',{request_id:id})).status,'approved');
 const updated=(await db.query(`select attachment_path from public.worker_document_statuses where id='${target}'`)).rows[0];assert.equal(updated.attachment_path,path);
 // A real sequence starts with a draft before the new object exists. The
 // formerly tested pre-inspected object without a draft cannot be created by
 // the inspection boundary and masked this lifecycle dependency.
 const stamp2=(await db.query(`select updated_at from public.worker_document_statuses where id='${target}'`)).rows[0].updated_at;
 const id2=uid(41), path2=`${company}/${worker}/${requirement}/${id2}/next.pdf`;
 await actor(owner); await rpc('prepare',{request_id:id2,status_id:target,expected_updated_at:stamp2,proposed:{attachment_paths:[path],notes:'updated',expires_at:null}});
 await db.exec('reset role');
 await db.exec(`insert into storage.objects(bucket_id,name,version) values('worker-documents','${path2}','v1');
 insert into private.document_upload_inspection_candidates(id,actor_id,company_id,worker_id,requirement_id,request_id,object_path,object_version,status,expires_at)
 values('${uid(51)}','${owner}','${company}','${worker}','${requirement}','${id2}','${path2}','v1','awaiting_inspection',clock_timestamp()+interval '2 minutes')`);
 const save=(await db.query(`select private.commit_document_upload_inspection_authorized('${uid(51)}','${id2}','v1',$1,16,'application/pdf') ok`,['b'.repeat(64)])).rows[0].ok;assert.equal(save,true);
 const proposed={attachment_paths:[path,path2],notes:'updated',expires_at:null};
 assert.equal((await db.query('select private.document_change_finalize_inspected_draft($1,$2::jsonb) ok',[id2,JSON.stringify(proposed)])).rows[0].ok,true);
 await actor(owner); assert.equal((await rpc('submit',{request_id:id2})).status,'pending');
 await db.exec('reset role'); assert.equal((await db.query('select private.document_change_finalize_inspected_draft($1,$2::jsonb) ok',[id2,JSON.stringify(proposed)])).rows[0].ok,false);
 await actor(reviewer); assert.equal((await rpc('approve',{request_id:id2})).status,'approved');
 assert.deepEqual((await db.query(`select attachment_paths from public.worker_document_statuses where id='${target}'`)).rows[0].attachment_paths,[path,path2]);
 console.log('offline overlay: OFF, outsider, self-review and modified version denied; authorized approval applied');
} finally { await db.close(); }
