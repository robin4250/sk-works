import test from 'node:test';
import assert from 'node:assert/strict';
import {processRecoveredSiteOrderReply} from './site_order_canonical_core.mjs';
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const packageId=id(1),leaseId=id(2),jobId=id(3),requestId=id(4),receiptId=id(5);
const claims={sub:id(6),session_id:id(7),role:'authenticated'};
const pdf=Buffer.from('%PDF-1.7\nfixed immutable bytes');
function database({saved=false,stored=false,denyLease=false,lostCommit=0}={}){
 const calls=[];let commit=0;
 return{calls,async query(sql,args){calls.push({sql,args});
  if(sql==='select session_user as role')return{rows:[{role:'postgres'}]};
  if(sql.includes('ready_recovered_reply'))return{rows:[{result:{package_id:packageId,job_id:jobId,request_id:requestId,reply_recipient_stored:stored,original_receipt_id:stored?receiptId:null}}]};
  if(sql.includes('require_reply_recovery_lease')&&denyLease)throw Error('private fixture reason');
  if(sql.startsWith('select evidence'))return{rows:[{evidence:{frozen:true}}]};
  if(sql.startsWith('select pdf_bytes'))return{rows:saved?[{pdf_bytes:pdf}]:[]};
  if(sql.includes('register_recovered_pdf'))return{rows:[{receipt:{job_id:jobId,receipt_id:receiptId,pdf_byte_length:pdf.length}}]};
  if(sql.includes('deliver_recovered_acceptance'))return{rows:[{result:{package_id:packageId,original_receipt_id:receiptId,status:'recipient_stored'}}]};
  if(sql==='commit'&&++commit===lostCommit)throw Error('lost fixture COMMIT reply');
  return{rows:[]};
 }};
}
test('fixed recovery worker uses current claims, server job and request only',async()=>{
 const db=database();let body;
 const result=await processRecoveredSiteOrderReply(db,packageId,leaseId,async e=>{body=e;return pdf;},claims);
 assert.equal(result.status,'recipient_stored');assert.deepEqual(body,{frozen:true});
 assert.equal(db.calls.filter(x=>x.sql.includes('set_config')).length,3);
 assert.ok(db.calls.filter(x=>x.sql.includes('set_config')).every(x=>x.args[0]===JSON.stringify(claims)));
 assert.deepEqual(db.calls.find(x=>x.sql.includes('register_recovered_pdf')).args,[jobId,pdf,leaseId]);
 assert.deepEqual(db.calls.find(x=>x.sql.includes('deliver_recovered_acceptance')).args,[packageId,receiptId,requestId,leaseId]);
 assert.ok(db.calls.findIndex(x=>x.sql.startsWith('select evidence'))<db.calls.findIndex(x=>x.sql.includes('require_reply_recovery_lease')));
});
test('a registered original is reused byte-for-byte without another renderer call',async()=>{
 const db=database({saved:true});await processRecoveredSiteOrderReply(db,packageId,leaseId,()=>{throw Error('must not render');},claims);
 assert.equal(db.calls.find(x=>x.sql.includes('register_recovered_pdf')).args[1],pdf);
});
test('already delivered result is read back without registration or redelivery',async()=>{
 const db=database({stored:true});const r=await processRecoveredSiteOrderReply(db,packageId,leaseId,()=>{throw Error('must not render');},claims);
 assert.equal(r.original_receipt_id,receiptId);assert.equal(db.calls.some(x=>/register_recovered|deliver_recovered/.test(x.sql)),false);
});
test('lease denial happens before rendering and is sanitized',async()=>{
 const db=database({denyLease:true});let rendered=false;
 await assert.rejects(()=>processRecoveredSiteOrderReply(db,packageId,leaseId,async()=>{rendered=true;return pdf;},claims),e=>e.message==='site_order_reply_rejected'&&!('cause' in e));
 assert.equal(rendered,false);assert.equal(db.calls.at(-1).sql,'rollback');
});
for(const phase of [1,2,3])test(`COMMIT ACK loss in phase ${phase} remains UNKNOWN without rollback or retry`,async()=>{
 const db=database({lostCommit:phase});await assert.rejects(()=>processRecoveredSiteOrderReply(db,packageId,leaseId,async()=>pdf,claims),/result_unknown/);
 assert.equal(db.calls.at(-1).sql,'commit');assert.equal(db.calls.filter(x=>x.sql==='commit').length,phase);
});
test('invalid identifiers never access a database',async()=>{
 const db=database();await assert.rejects(()=>processRecoveredSiteOrderReply(db,'not-id',leaseId,async()=>pdf,claims));
 assert.equal(db.calls.length,0);
});
