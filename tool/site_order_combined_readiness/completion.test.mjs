import test from 'node:test';
import assert from 'node:assert/strict';
import {requireCompletion} from './completion.mjs';
const receipts = [
 {combined_compatibility_installed:true,only_six_function_bodies_and_named_check_changed:true,late_compat_failure_rolled_back:true},
 {registered_targets_in_full_actual_composition:true,selected_returned_trade_used_for_prepare:true,negative_cases:9},
 {actual_public_jwt_bodies_and_fixture_live_sid_consumer_smoke:true,old_qualification_personnel_read_save_retransfer:true,mixed_batches_denied_without_mutation:true},
 {consent_source_only:true,exact_eight_c_unchanged:true,actual_public_uid_jwt_bodies:2},
 {result:'PASS public-reconstructed exact-eight-body fourteen-module composition',full_modules:14,checks:315},
].map(receipt=>({...receipt,production_changed:false}));
const output=values=>values.map(value=>JSON.stringify(value)).join('\n');
test('requires every bounded completion receipt exactly once',()=>assert.equal(requireCompletion(output(receipts)),true));
test('zero exit with runtime fatal or missing final evidence is rejected',()=>{
 for(let index=0;index<receipts.length;index++)assert.throws(()=>requireCompletion(output(receipts.filter((_,i)=>i!==index))+'\nfatal library error, lookup self'));
});
test('duplicate, malformed, wrong scope and false success are rejected',()=>{
 assert.throws(()=>requireCompletion(output([...receipts,receipts[4]])));
 assert.throws(()=>requireCompletion(output([...receipts,{...receipts[0],combined_compatibility_installed:false}])));
 assert.throws(()=>requireCompletion(output([...receipts,{...receipts[4],production_changed:true}])));
 assert.throws(()=>requireCompletion(output(receipts)+'\n{broken'));
 for(const patch of [{checks:314},{full_modules:13},{production_changed:true},{result:'partial'}])assert.throws(()=>requireCompletion(output([...receipts.slice(0,4),{...receipts[4],...patch}])));
});
