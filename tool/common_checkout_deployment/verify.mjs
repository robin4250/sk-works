// Extends the immutable 118-check source fixture, never a production connection.
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
let source=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
if(createHash('sha256').update(source).digest('hex')!=='a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a')throw Error('Reviewed 118-check fixture changed');
source=source.replace("import {readFile, mkdtemp, rm}","import {readFile, mkdtemp, rm, writeFile}");
const start=source.indexOf(" phase='source-bound-review-unit';");
const end=source.indexOf(' await exec(`create trigger attendance_refresh_payroll',start);
if(start<0||end<0)throw Error('Reviewed fixture setup anchors differ');
source=source.slice(0,start)+` phase='bounded-before-install-and-unused-restore';
 await exec("create table public.payroll_adjustments(id uuid,payload text);insert into public.payroll_adjustments values('00000000-0000-0000-0000-000000000901','opaque financial sentinel');");
 await exec("insert into public.payroll_statements(company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,workflow_state,automatic_calculation) values('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902','2019-01-01','2019-01-31',777,7,770,'finalized',false)");
 const inventorySQL=await readFile('tool/common_checkout_deployment/inventory.read-only.sql','utf8');
 const deploymentBefore=(await client.query(inventorySQL)).rows[0].inventory;
 const observed=join(root,'before.json'),prepared=join(root,'prepared');
 await writeFile(observed,JSON.stringify(deploymentBefore));
 await run('python3',['tool/common_checkout_deployment/prepare.py','--snapshot',observed,'--output',prepared]);
 const installSQL=await readFile(join(prepared,'private-install.sql.review-only'),'utf8');
 const restoreSQL=await readFile(join(prepared,'private-unused-restore.sql.review-only'),'utf8');
 const status=JSON.parse(await readFile(join(prepared,'prepare-status.json'),'utf8'));
 const pins={after_source_md5:status.changed_routines};
 await exec('alter function private.account_access_allowed() volatile');
 await reject(()=>exec(installSQL),/Bounded checkout before inventory differs/);await exec('rollback');
 await exec('alter function private.account_access_allowed() stable');
 eq((await client.query(inventorySQL)).rows[0].inventory,deploymentBefore,'Refused drift has no financial/schema side effect');
 await exec(installSQL);
 eq((await client.query(inventorySQL)).rows[0].inventory.data,deploymentBefore.data,'Bounded DDL install preserves all original financial fingerprints');
 await reject(()=>exec(installSQL),/inventory differs|schema already exists/);await exec('rollback');
 await exec(restoreSQL);
 eq((await client.query(inventorySQL)).rows[0].inventory,deploymentBefore,'Unused restore returns exact original catalog and financial hashes');
 await exec(installSQL);
 for(const [signature,expected]of Object.entries(pins.after_source_md5))eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[signature]),expected,'Bounded reinstall exact source');
`+source.slice(end);
const anchor=" phase='source-and-settings-preservation';";
if(source.split(anchor).length!==2)throw Error('Reviewed used-restore anchor differs');
source=source.replace(anchor,` phase='used-restore-prohibited';
 await reject(()=>exec(restoreSQL),/inventory differs|already used/);await exec('rollback');
 console.log(JSON.stringify({bounded_install_proof:true,source_drift_refused:true,financial_hashes_preserved:true,unused_restore_exact:true,retry_refused:true,used_restore_refused:true,production_changed:false}));
`+anchor);
const dir=await mkdtemp(join(tmpdir(),'sko-checkout-deployment-proof-'));
try{const file=join(dir,'proof.mjs');await writeFile(file,source);const r=await promisify(execFile)(process.execPath,[file,process.argv[2]],{env:process.env,maxBuffer:1024*1024});process.stdout.write(r.stdout);process.stderr.write(r.stderr);}
catch(error){process.stdout.write(error.stdout??'');process.stderr.write(error.stderr??'');process.exitCode=1;}
finally{await rm(dir,{recursive:true,force:true});}
