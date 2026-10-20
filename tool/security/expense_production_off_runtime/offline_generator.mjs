// Offline only. Built-ins and hash-pinned original modules; no DB or network client.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {isDeepStrictEqual} from 'node:util';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const runtime=path.dirname(fileURLToPath(import.meta.url));
const pins={
 'expense_default_off_plan.mjs':'5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9',
 'source/expense_direction_code_checkpoint.mjs':'9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f',
 'source/expense_direction_default_off_preparation.mjs':'5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8',
 'source/expense_payment_direction_v2_20261019.sql.review-only':'770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a',
};
const sha=b=>createHash('sha256').update(b).digest('hex');
function writeOnce(name,value){
 const file=path.join(process.argv[3],name);
 if(fs.existsSync(file)){assert.equal(fs.readFileSync(file,'utf8'),value,'existing artifact differs');return;}
 fs.writeFileSync(file,value,{mode:0o600,flag:'wx'});
}
try {
 assert(['verify','classify'].includes(process.argv[2]));
 for(const [file,hash]of Object.entries(pins)){
  const full=path.join(runtime,file);assert(!fs.lstatSync(full).isSymbolicLink());
  assert.equal(sha(fs.readFileSync(full)),hash,'original module changed');
 }
 const {buildExpensePlan,prepareUnusedUndo}=await import('./expense_default_off_plan.mjs');
 const stage=process.argv[3];
 const before=JSON.parse(fs.readFileSync(path.join(stage,'private-fresh-before.json'),'utf8'));
 const candidate=fs.readFileSync(path.join(runtime,'source/expense_payment_direction_v2_20261019.sql.review-only'),'utf8');
 const plan=buildExpensePlan(before,candidate);
 assert.equal(plan.install,fs.readFileSync(path.join(stage,'private-prepared-install.sql.review-only'),'utf8'));
 assert.equal(plan.readActualAfter,fs.readFileSync(path.join(stage,'private-read-actual-after.sql.read-only'),'utf8'));
 if(process.argv[2]==='verify'){
  assert.equal((plan.install.match(/^COMMIT;$/gm)||[]).length,1);
  assert(plan.install.includes('SET LOCAL ROLE postgres;'));
  writeOnce('private-verified-plan.json',JSON.stringify({schema:1,verified:true,install_sha256:sha(plan.install),read_after_sha256:sha(plan.readActualAfter)}));
 }else{
  const actual=JSON.parse(fs.readFileSync(path.join(stage,'private-production-actual-after.json'),'utf8'));
  assert.equal(actual.read_only,'on');
  if(isDeepStrictEqual(actual.after,before.before)&&actual.business===before.business&&
     actual.v2_or_basis_count===0&&actual.converter_installed===false&&actual.audit_installed===false&&actual.rollout_installed===false){
   writeOnce('classification.json',JSON.stringify({schema:1,state:'before_state_observed',retry_allowed:false}));
  }else{
   const undo=prepareUnusedUndo(before,actual);
   writeOnce('private-production-unused-undo.sql.review-only',undo);
   writeOnce('classification.json',JSON.stringify({schema:1,state:'installed_off_unused_undo_candidate',retry_allowed:false,undo_sha256:sha(undo)}));
  }
 }
}catch{process.stderr.write('offline_expense_verification_failed\n');process.exitCode=1;}
