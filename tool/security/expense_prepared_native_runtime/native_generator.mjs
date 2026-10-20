import fs from 'node:fs';
import {buildExpensePlan,prepareUnusedUndo} from './expense_default_off_plan.mjs';
const actualBefore=JSON.parse(fs.readFileSync('private-fresh-before.json','utf8'));
const candidate=fs.readFileSync('source/expense_payment_direction_v2_20261019.sql.review-only','utf8');
const original=buildExpensePlan(actualBefore,candidate);
if(original.install!==fs.readFileSync('private-prepared-install.sql.review-only','utf8')||original.readActualAfter!==fs.readFileSync('private-read-actual-after.sql.read-only','utf8'))throw Error('prepared_source_mismatch');
if(fs.existsSync('private-clone-local-before.json')){
 const before=JSON.parse(fs.readFileSync('private-clone-local-before.json','utf8'));
 if(before.clone_local_fixture!==true)throw Error('clone_label_required');
 if(fs.existsSync('private-clone-actual-after.json')){
  fs.writeFileSync('private-clone-unused-undo.sql.review-only',prepareUnusedUndo(before,JSON.parse(fs.readFileSync('private-clone-actual-after.json','utf8'))),{mode:0o600,flag:'wx'});
 }else{
  const plan=buildExpensePlan(before,candidate);
  for(const [name,value]of Object.entries({'private-clone-install.sql.review-only':plan.install,'private-clone-read-after.sql.read-only':plan.readActualAfter}))fs.writeFileSync(name,value,{mode:0o600,flag:'wx'});
 }
}
