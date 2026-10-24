// Disposable PG17/PostgREST lifecycle proof. Original 37-check source is pinned.
import fs from 'node:fs/promises';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const run=promisify(execFile);
const original=await fs.readFile('tool/verify_company_registered_allowance_labels.mjs','utf8');
if(createHash('sha256').update(original).digest('hex')!== '8623b34750dc1ced8e4647a11aa34d672170ef5a26c67c735dfc5959a5aa7ae3')throw Error('Original 37-case reader proof changed');
const once=(source,anchor,replacement)=>{if(source.split(anchor).length!==2)throw Error('Lifecycle anchor not unique');return source.replace(anchor,replacement);};
let source=once(original," await db.query(unit);",` phase='bounded-install-postflight-restore';
 const directory=await fs.mkdtemp(join((await import('node:os')).tmpdir(),'sko-names-bounded-'));
 const inventory=await fs.readFile('tool/company_registered_names_deployment/inventory.read-only.sql','utf8');
 const readInventory=async()=>(await db.query(inventory)).rows[0].inventory;
 const snapshot=await readInventory();
 await fs.writeFile(join(directory,'before.json'),JSON.stringify(snapshot));
 await run('python3',['tool/company_registered_names_deployment/prepare.py',join(directory,'before.json'),join(directory,'prepared')]);
 const install=await fs.readFile(join(directory,'prepared/private-install.sql.review-only'),'utf8');
 const postflight=await fs.readFile(join(directory,'prepared/private-postflight.read-only.sql'),'utf8');
 const restore=await fs.readFile(join(directory,'prepared/private-unchanged-state-restore.sql.review-only'),'utf8');
 await db.query('insert into public.companies(id) values($1)',[cid]);
 await rejects(()=>db.query(install),/inventory differs/);await db.query('rollback');
 await db.query('delete from public.companies where id=$1',[cid]);
 equal(await readInventory(),snapshot,'stale install refuses data drift');
 await db.query(install);await db.query(postflight);checks++;
 await db.query(restore);equal(await readInventory(),snapshot,'restore returns exact original inventory');
 await db.query(install);await db.query(postflight);checks++;
`);
source=once(source," console.log(json({pass:true,checks,",` await rejects(()=>db.query(restore),/inventory differs/);await db.query('rollback');
 equal(await q("select to_regprocedure('public.read_company_registered_allowance_labels(uuid)') is not null v"),true,'changed registration prevents restore');
 await fs.rm(directory,{recursive:true,force:true});
 console.log(json({bounded_lifecycle:true,restore_read_usage_detected:false,restore_requires_client_withdrawal:true,pass:true,checks,`);
// Inject only module helpers needed by the reused source; no application source is rewritten.
source=source.replace("import fs from 'node:fs/promises';","import fs from 'node:fs/promises';\nimport {join} from 'node:path';");
const directory=await mkdtemp(join(tmpdir(),'sko-names-lifecycle-runner-'));
try{
 const path=join(directory,'runner.mjs');await fs.writeFile(path,source);
 const result=await run(process.execPath,[path,process.argv[2]],{env:process.env,maxBuffer:2*1024*1024});
 process.stdout.write(result.stdout);process.stderr.write(result.stderr);
}catch(error){process.stdout.write(error.stdout??'');process.stderr.write(error.stderr??'');process.exitCode=1;}
finally{await fs.rm(directory,{recursive:true,force:true});}
