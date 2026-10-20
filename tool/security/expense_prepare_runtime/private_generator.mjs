import fs from'node:fs';import{buildExpensePlan}from'./expense_default_off_plan.mjs';
try {
 const record=JSON.parse(fs.readFileSync('private-fresh-before.json','utf8'));
 const candidate=fs.readFileSync('source/expense_payment_direction_v2_20261019.sql.review-only','utf8');
 const result=buildExpensePlan(record,candidate);
 for(const [name,value]of Object.entries({'private-prepared-install.sql.review-only':result.install,'private-read-actual-after.sql.read-only':result.readActualAfter}))fs.writeFileSync(name,value,{mode:0o600,flag:'wx'});
}catch{process.exitCode=1;}
