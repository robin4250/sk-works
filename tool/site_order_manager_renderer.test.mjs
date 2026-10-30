import test from 'node:test';
import assert from 'node:assert/strict';
import {registerManagerCanonicalSiteOrderJob} from './site_order_canonical_renderer.mjs';
const id='00000000-0000-0000-0000-000000009304';
const pdf=Buffer.from('%PDF-1.7\nimmutable-manager-original\n%%EOF');
function database({original=false,accessDenied=false,scopeDenied=false,jobMissing=false,commitUnknown=false}={}){
 const calls=[];return{calls,async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return{rows:[{role:'postgres'}]};
  if(sql==='select private.require_standalone_trade_document_access()'&&accessDenied)throw Error('private detail must not escape');
  if(sql.startsWith('select j.evidence'))return{rows:jobMissing?[]:[{evidence:{body:{scope:'site'}}}]};
  if(sql.startsWith('select site_order_manager_private.require_actor')&&scopeDenied)throw Error('scope denied');
  if(sql.startsWith('select pdf_bytes'))return{rows:original?[{pdf_bytes:pdf}]:[]};
  if(sql.startsWith('select site_order_manager_private.register_canonical_pdf'))return{rows:[{receipt:{job_id:id,pdf_byte_length:args[1].length}}]};
  if(sql==='commit'&&commitUnknown)throw Error('ack lost');
  return{rows:[]};
 }};
}
test('manager export uses fixed actor, registry and generated registration policy',async()=>{
 const db=database();let seen;
 await registerManagerCanonicalSiteOrderJob(db,id,async e=>{seen=e;return pdf;});
 assert.deepEqual(seen,{body:{scope:'site'}});
 const access=db.calls.findIndex(x=>x.sql==='select private.require_standalone_trade_document_access()');
 const lock=db.calls.findIndex(x=>x.sql.startsWith('select j.evidence'));
 const scope=db.calls.findIndex(x=>x.sql.startsWith('select site_order_manager_private.require_actor'));
 const original=db.calls.findIndex(x=>x.sql.startsWith('select pdf_bytes'));
 assert.ok(access<lock&&lock<scope&&scope<original);
 assert.match(db.calls[lock].sql,/document_scopes/);assert.match(db.calls[lock].sql,/connection_fingerprint/);
 assert.equal(db.calls.some(x=>x.sql.startsWith('select site_order_artifact_private.register_canonical_pdf')),false);
 assert.equal(db.calls[0].sql,'begin isolation level read committed');
});
for(const option of ['accessDenied','scopeDenied','jobMissing'])test(`${option} never renders or returns private diagnostics`,async()=>{
 const db=database({[option]:true});let renders=0;
 await assert.rejects(()=>registerManagerCanonicalSiteOrderJob(db,id,async()=>{renders++;return pdf;}),e=>e.message==='canonical_registration_rejected'&&!('cause' in e));
 assert.equal(renders,0);assert.equal(db.calls.at(-1).sql,'rollback');
});
test('manager original retry never invokes renderer',async()=>{
 const db=database({original:true});await registerManagerCanonicalSiteOrderJob(db,id,async()=>{throw Error('must not render');});
 assert.equal(db.calls.at(-1).sql,'commit');
});
test('manager unknown commit has no automatic resend',async()=>{
 const db=database({commitUnknown:true});
 await assert.rejects(()=>registerManagerCanonicalSiteOrderJob(db,id,async()=>pdf),/canonical_commit_result_unknown/);
 assert.equal(db.calls.at(-1).sql,'commit');
 assert.equal(db.calls.filter(x=>x.sql.startsWith('select site_order_manager_private.register_canonical_pdf')).length,1);
});
