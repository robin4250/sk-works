import test from 'node:test';
import assert from 'node:assert/strict';
import {registerCanonicalSiteOrderJob} from './site_order_canonical_renderer.mjs';
const id='00000000-0000-0000-0000-000000009304';
const pdf=Buffer.from('%PDF-1.7\nimmutable-test-original\n%%EOF');
function database({stored=false,role='postgres',renderDenied=false,commitUnknown=false}={}) {
 const calls=[];
 return {calls,async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return{rows:[{role}]};
  if(sql.startsWith('select j.evidence'))return{rows:[{evidence:{body:{unchanged:true}}}]};
  if(sql.startsWith('select pdf_bytes'))return{rows:stored?[{pdf_bytes:pdf}]:[]};
  if(sql.includes('register_canonical_pdf')){
   if(renderDenied)throw Error('session revoked');
   return{rows:[{receipt:{job_id:id,pdf_byte_length:args[1].length,pdf_sha256:'server-computed'}}]};
  }
  if(sql==='commit'&&commitUnknown)throw Error('ack lost');
  return{rows:[]};
 }};
}
test('only DB evidence reaches renderer and receipt follows commit',async()=>{
 const db=database();let evidence;
 const receipt=await registerCanonicalSiteOrderJob(db,id,async e=>{evidence=e;return pdf;});
 assert.deepEqual(evidence,{body:{unchanged:true}});
 assert.equal(db.calls[0].sql,'begin isolation level read committed');
 assert.equal(receipt.pdf_sha256,'server-computed');
 assert.equal(db.calls.at(-1).sql,'commit');
 assert.deepEqual(db.calls.find(c=>c.sql.includes('register_canonical_pdf')).args,[id,pdf]);
});
test('exact retry never regenerates timestamp-varying PDF',async()=>{
 const db=database({stored:true});
 await registerCanonicalSiteOrderJob(db,id,async()=>{throw Error('must not rerender');});
 assert.deepEqual(db.calls.find(c=>c.sql.includes('register_canonical_pdf')).args[1],pdf);
 const lock=db.calls.findIndex(c=>c.sql.startsWith('select j.evidence'));
 const original=db.calls.findIndex(c=>c.sql.startsWith('select pdf_bytes'));
 assert.ok(lock>=0&&original>lock,'Read original in a fresh statement after the job lock');
});
test('client/service connection is rejected before loading evidence',async()=>{
 const db=database({role:'service_role'});
 await assert.rejects(()=>registerCanonicalSiteOrderJob(db,id,async()=>pdf),/registration_rejected/);
 assert.equal(db.calls.some(c=>c.sql.startsWith('select j.evidence')),false);
 assert.equal(db.calls.at(-1).sql,'rollback');
});
test('registration recheck refusal rolls back and never reports success',async()=>{
 const db=database({renderDenied:true});
 await assert.rejects(()=>registerCanonicalSiteOrderJob(db,id,async()=>pdf),error=>error.message==='canonical_registration_rejected'&&!('cause' in error));
 assert.equal(db.calls.at(-1).sql,'rollback');
 assert.equal(db.calls.some(c=>c.sql==='commit'),false);
});
test('commit ACK loss stays unknown and is never retried or rolled back',async()=>{
 const db=database({commitUnknown:true});
 await assert.rejects(()=>registerCanonicalSiteOrderJob(db,id,async()=>pdf),/commit_result_unknown/);
 assert.equal(db.calls.at(-1).sql,'commit');
 assert.equal(db.calls.filter(c=>c.sql.includes('register_canonical_pdf')).length,1);
});
test('invalid job ID never touches a DB',async()=>{
 const db=database();await assert.rejects(()=>registerCanonicalSiteOrderJob(db,'bad',async()=>pdf),/job_id_required/);
 assert.equal(db.calls.length,0);
});
