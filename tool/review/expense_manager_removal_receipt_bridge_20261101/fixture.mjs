import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {prepare as canonicalPrepare,id,info} from '../expense_manager_removal_receipt_binding_20261101/fixture.mjs';
export {info};
export async function prepare(Client){
 assert.equal(createHash('sha256').update(fs.readFileSync('docs/candidates/expense_manager_removal_receipt_binding_20261101.sql.review-only')).digest('hex'),'90abf05911bfbe0866cdb1bdfea256358d43f9704076a5139da6df08222cc6d6');
 const {config,admin}=await canonicalPrepare(Client);
 try{
 await admin.query(`set test.uid='${info.applicant}';set test.sid='${info.applicantSid}';set role authenticated`);
 const receipt=(await admin.query('select public.expense_prepare_receipt($1,$2,$3,$4,4,$5) value',[info.claim,info.company,info.worker,'a'.repeat(64),'image/jpeg'])).rows[0].value;
 assert.equal(receipt.attached,false);assert.equal(receipt.uploaded,false);
 await admin.query(`insert into storage.objects(bucket_id,name,metadata) values('expense-receipts',$1,'{"size":4,"mimetype":"image/jpeg"}')`,[receipt.object_path]);
 const submitted=(await admin.query('select public.expense_personal_submit_with_receipt($1,$2,$3,current_date,$4,1234) value',[info.claim,info.company,info.worker,'Canonical bridge receipt'])).rows[0].value;
 assert.equal(submitted.receipt_object_path,receipt.object_path);
 await admin.query('reset role');
 const original=(await admin.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[info.claim])).rows[0].value;
 assert.equal(Object.hasOwn(original,'receipt_object_path'),false);
 const metadata=(await admin.query('select to_jsonb(e) value from private.expense_receipts e where claim_id=$1',[info.claim])).rows[0].value;
 const objectMetadata=(await admin.query('select to_jsonb(e) value from storage.objects e where name=$1',[receipt.object_path])).rows[0].value;
 assert.equal(metadata.attached,true);assert.equal(metadata.sha256,'a'.repeat(64));
 return {config,admin,baseline:{original,metadata,objectMetadata},canonicalPath:receipt.object_path};
 }catch(error){await admin.end().catch(()=>{});throw error;}
}
