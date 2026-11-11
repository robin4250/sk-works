// New CLI protocol boundary only, reusing the owner's synthetic engine verifier.
// Explicit local source/fixture dependencies; never opens a remote database.
import fs from 'node:fs';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';import {pathToFileURL} from 'node:url';
const [source,repo,runtime,catalog]=process.argv.slice(2);if(!source||!repo||!runtime||!catalog)throw Error('explicit source, fixture, PGlite and source-only checkpoint paths required');
const fixtureURL=pathToFileURL(source+'/verify_stage3.mjs').href;
let script=fs.readFileSync(new URL(fixtureURL),'utf8');
const beforeAnchor='const before=await capture();',afterAnchor='const after=await capture();';
for(const anchor of [beforeAnchor,afterAnchor])assert.equal(script.split(anchor).length,2,'fixture hook anchor drift');
script=script.replaceAll('import.meta.url',JSON.stringify(fixtureURL))
 .replace("from'./stage3_plan.mjs'",'from'+JSON.stringify(pathToFileURL(source+'/stage3_plan.mjs').href))
 .replace("import('./stage2_plan_reference.mjs')",'import('+JSON.stringify(pathToFileURL(source+'/stage2_plan_reference.mjs').href)+')')
 .replace("import('./source/expense_direction_default_off_preparation.mjs')",'import('+JSON.stringify(pathToFileURL(source+'/source/expense_direction_default_off_preparation.mjs').href)+')');
script=script.replace(beforeAnchor,beforeAnchor+'globalThis.cliBefore=structuredClone(before);globalThis.cliBinding=structuredClone(b);')
 .replace(afterAnchor,afterAnchor+'globalThis.cliAfter=structuredClone(after);');
process.argv=['node',source+'/verify_stage3.mjs',repo,runtime,catalog];
await import('data:text/javascript;base64,'+Buffer.from(script).toString('base64'));
assert.equal(process.exitCode??0,0,'engine fixture must pass before CLI protocol checks');
const before=globalThis.cliBefore,after=globalThis.cliAfter,binding=globalThis.cliBinding;
const maintenanceText=fs.readFileSync(source+'/maintenance.sql.review-only','utf8');
const direct=await import(pathToFileURL(source+'/stage3_plan.mjs'));
function cli(mode,input){const r=spawnSync(process.execPath,[source+'/stage3_plan.mjs',mode],{input:JSON.stringify(input),encoding:'utf8',maxBuffer:16777216,timeout:25000,env:{PATH:process.env.PATH}});assert.equal(r.status,0,'offline CLI refused '+mode);return JSON.parse(r.stdout);}
assert.equal(cli('capture-sql',{binding}).sql,direct.captureSql(binding));
assert.equal(cli('install',{before,maintenanceText,binding}).sql,direct.buildInstall(before,maintenanceText,binding));
assert.deepEqual(cli('classify',{before,after,binding}),{state:'converted_target_verified',retry_allowed:false});
assert.deepEqual(cli('classify',{before,after:before,binding}),{state:'before_state_observed',retry_allowed:false});
assert.deepEqual(cli('classify',{before,after:{},binding}),{state:'state_requires_review',retry_allowed:false});
console.log('PASS 5 stage3 offline CLI protocol checks: capture/install byte equality, success/before/unknown classifications; no production connection');
