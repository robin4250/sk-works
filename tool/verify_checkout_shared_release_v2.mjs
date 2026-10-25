// Runs the unchanged canonical parent chain once, then each distinct v2 unit
// once in that same isolated database. No case or assertion is filtered out.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/verify_checkout_shared_hours_v2.mjs','utf8');
const marker=" console.log(JSON.stringify({pass:true,versioned_work_report_then_individual_hours:true,first_work_signature_preserved:true,stale_and_direct_supervisor_bypass_denied:true,actual_payroll_quantities:[7.25,6.75],legacy_reports_preserved:true,real_gotrue:false,production_changed:false}));";
assert.equal(original.split(marker).length,2,'Exact normal proof completion marker');
const units=[];
for(const name of ['managed','approved']){
 const source=await readFile('tool/verify_checkout_shared_'+name+'_v2.mjs','utf8');
 const start='const addition=String.raw`',end='`;\nconst folder=';
 assert.equal(source.split(start).length,2,'One trusted literal proof addition for '+name);
 const body=source.slice(source.indexOf(start)+start.length);
 assert.equal(body.split(end).length,2,'One trusted literal proof terminator for '+name);
 const addition=body.slice(0,body.indexOf(end));
 assert.ok(!addition.includes('`'),'Proof addition cannot escape the enclosing literal');
 units.push('\n{\n'+addition+'\n}\n');
}
const generated=original.replace(marker,()=>marker+units.join('')+"\n console.log(JSON.stringify({pass:true,canonical_parent_runs:1,normal_v2_runs:1,managed_v2_runs:1,approved_v2_runs:1,all_original_assertions_retained:true,real_gotrue:false,production_changed:false}));");
const folder=await mkdtemp(join(tmpdir(),'shared-release-v2-proof-'));
try{
 const file=join(folder,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
