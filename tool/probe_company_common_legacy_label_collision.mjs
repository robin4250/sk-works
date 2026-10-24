// Diagnostic only; never fixes or deploys the observed behavior.
// Reuses the immutable source-bound 118-check disposable fixture.
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const original=await readFile('tool/verify_company_checkout_integration.mjs','utf8');
if(createHash('sha256').update(original).digest('hex')!=='a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a')throw Error('118-check fixture source changed; review diagnostic anchors');
const replaceOnce=(s,a,b)=>{if(s.split(a).length!==2)throw Error('Diagnostic anchor not unique');return s.replace(a,b);};
let source=replaceOnce(original," const settingsBefore=await q(",` const COLLISION_WORKER=id(27);
 await client.query("insert into workers(id,company_id,name) values($1,$2,'同名経路調査専用社員')",[COLLISION_WORKER,A]);
 await client.query("insert into worker_payroll_settings(company_id,worker_id,allowance_name_1,allowance_1) values($1,$2,$3,700)",[A,COLLISION_WORKER,days[0].name_snapshot]);
 const settingsBefore=await q(`);
source=replaceOnce(source," phase='source-and-settings-preservation';",` phase='diagnostic-new-common-versus-personal-legacy-label';
 const collisionReport=await draft('2020-10-12',COLLISION_WORKER,[days[0]]);await sign(collisionReport);
 const collisionSalary=await statement(COLLISION_WORKER);
 eq(collisionSalary.gross_pay,10800,'DIAGNOSTIC: new company100 and legacy text700 both monetize the same selected label');
 eq(collisionSalary.detail.custom_earnings_total,100,'DIAGNOSTIC: captured company source pays100');
 eq(collisionSalary.detail[days[0].name_snapshot],700,'DIAGNOSTIC: old legacy-label path also pays700');
 console.log(JSON.stringify({diagnostic:'new_common_personal_legacy_label_collision',reproduced:true,
  base_pay:10000,registered_company_rate:100,stored_personal_legacy_rate:700,observed_gross:collisionSalary.gross_pay,
  expected_company_choice_only_gross:10100,duplicate_legacy_amount:700,production_changed:false,
  fix_implemented:false,blocker_open:true}));
 phase='source-and-settings-preservation';`);
const dir=await mkdtemp(join(tmpdir(),'sko-common-label-diagnostic-'));
try{
 const file=join(dir,'diagnostic.mjs');await writeFile(file,source);
 const {stdout,stderr}=await promisify(execFile)(process.execPath,[file,process.argv[2]],{env:process.env,maxBuffer:1024*1024});
 process.stdout.write(stdout);process.stderr.write(stderr);
}catch(error){process.stdout.write(error.stdout??'');process.stderr.write(error.stderr??'');process.exitCode=1;}
finally{await rm(dir,{recursive:true,force:true});}
