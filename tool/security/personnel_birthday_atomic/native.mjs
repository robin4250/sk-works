// Run only the saved personnel bootstrap, then NEW atomic composition cases.
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd(),fixture=join(root,'tool/security/personnel_write/verify.mjs');
const url=new URL(process.env.SKO_PERSONNEL_FIXTURE_URL??'');
if(!['127.0.0.1','localhost'].includes(url.hostname)||url.port!=='5432'||url.pathname!=='/sko_personnel_fixture'||url.username!=='postgres'||url.password!=='fixture-only'||url.search||url.hash)throw Error('Dedicated disposable NativePG17 only');
let source=await readFile(fixture,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('Saved personnel foundation drift');
const anchor='const baseline=await capsule();';if(source.split(anchor).length!==2)throw Error('Bootstrap cutoff drift');
source=source.split(anchor)[0];
const here="const here=path.dirname(fileURLToPath(import.meta.url));";if(source.split(here).length!==2)throw Error('Fixture root anchor drift');
source=source.replace(here,()=> 'const here='+JSON.stringify(dirname(fixture))+';');
const tail=await readFile('tool/security/personnel_birthday_atomic/check-body.mjs','utf8');
const folder=await mkdtemp(join(tmpdir(),'sko-personnel-birthday-atomic-'));
try{
 const file=join(folder,'native.mjs');await writeFile(file,source+tail);
 const syntax=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});if(syntax.status!==0)throw Error(syntax.stderr);
 const result=spawnSync(process.execPath,[file,resolve(process.argv[2])],{stdio:'inherit',cwd:root,env:process.env});
 if(result.status!==0)process.exitCode=result.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
