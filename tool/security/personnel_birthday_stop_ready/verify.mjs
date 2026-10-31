// Runs only the immutable personnel fixture bootstrap, never the older suites.
import fs from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../..');
const fixtureRoot=process.env.SKO_PERSONNEL_FOUNDATION_ROOT||root;
const foundation=path.join(fixtureRoot,'tool/security/personnel_write/verify.mjs');
const original=fs.readFileSync(foundation,'utf8');
if(createHash('sha256').update(original).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('Personnel bootstrap drift');
const cutoff='const baseline=await capsule();';
if(original.split(cutoff).length!==2)throw Error('Bootstrap cutoff drift');
if(process.env.SKO_PERSONNEL_FIXTURE_URL){
 const u=new URL(process.env.SKO_PERSONNEL_FIXTURE_URL);
 if(!['127.0.0.1','localhost'].includes(u.hostname)||u.port!=='5432'||u.pathname!=='/sko_personnel_fixture'||u.username!=='postgres'||u.password!=='fixture-only'||u.search||u.hash)throw Error('Disposable loopback fixture credentials only');
}
if(!process.argv[2])throw Error('Pass PGlite module or the guarded personnel_rls/pg_adapter.mjs');
const scenario=process.argv[3];
if(!['stop','zero-use-reopen'].includes(scenario)||process.argv.length!==4)throw Error('Explicit scenario must be stop or zero-use-reopen');
let source=original.split(cutoff)[0].replace('const here=path.dirname(fileURLToPath(import.meta.url));','const here='+JSON.stringify(path.dirname(foundation))+';');
source+='\nconst stopReadyScenario='+JSON.stringify(scenario)+';\nconst stopReadyRoot='+JSON.stringify(root)+';\nconst dependenciesRoot='+JSON.stringify(process.env.SKO_PERSONNEL_DEPENDENCIES_ROOT||path.join(fixtureRoot,'tool/security/fixture_dependencies'))+';\n';
source+=fs.readFileSync(path.join(here,'check-body.mjs'),'utf8');
const folder=fs.mkdtempSync(path.join(tmpdir(),'sko-stop-ready-'));
try{
 const script=path.join(folder,'synthetic.mjs');fs.writeFileSync(script,source);
 const run=spawnSync(process.execPath,[script,path.resolve(process.argv[2])],{stdio:'inherit'});
 process.exitCode=run.status??1;
}finally{fs.rmSync(folder,{recursive:true,force:true});}
