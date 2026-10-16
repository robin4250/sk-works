import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const sourceHash='79c128c9c03c138084712512ebfcaa1e68cdd5b2641f02cf7c17cc6b99b3e655';
const anchor=" phase='original-app-fixtures';";
export function instrumentSessionLifecycle(source,{adapterUrl,checkUrl}) {
 if(createHash('sha256').update(source).digest('hex')!==sourceHash)throw Error('Original GoTrue fixture source drift');
 if(source.split(anchor).length!==2)throw Error('Original GoTrue fixture anchor drift');
 for(const contract of ["if(url.origin!==api.origin)throw Error('Nonlocal request refused')", "started=true;await cli(['start'", "await cli(['stop','--no-backup']", "assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0", "finally{", "phase='original-master-and-identities-preserved'"]){
  if(!source.includes(contract))throw Error('Original GoTrue fixture safety contract drift');
 }
 if(!adapterUrl.startsWith('file:')||!checkUrl.startsWith('file:'))throw Error('Fixture imports must be local files');
 const oldImport="import {sanitizePlatformRows} from './platform_log_adapter.mjs';";
 if(source.split(oldImport).length!==2)throw Error('Original adapter import drift');
 const hook=" phase='real-session-lifecycle';\n await __verifySessionLifecycle({request,db,password,claims,guardedSessions:[master,normalAdmin,other]});\n";
 return `import {verifySessionLifecycle as __verifySessionLifecycle} from ${JSON.stringify(checkUrl)};\n`+
 source.replace(oldImport,`import {sanitizePlatformRows} from ${JSON.stringify(adapterUrl)};`).replace(anchor,hook+anchor);
}
async function run() {
 if(!process.env.CI||!process.env.RUNNER_TEMP||Object.keys(process.env).some(k=>/^SUPABASE_/.test(k)))throw Error('Credential-free disposable CI required');
 const root=process.cwd(),security=path.join(root,'tool/security');
 const source=await fs.readFile(path.join(security,'platform_auth_gotrue_e2e.mjs'),'utf8');
 const generated=instrumentSessionLifecycle(source,{adapterUrl:pathToFileURL(path.join(security,'platform_log_adapter.mjs')).href,checkUrl:pathToFileURL(path.join(security,'auth_session_lifecycle_check.mjs')).href});
 const parent=path.resolve(process.env.RUNNER_TEMP);if(parent==='/'||parent===root)throw Error('Private fixture directory required');
 const owned=await fs.mkdtemp(path.join(parent,'sko-auth-lifecycle-source-'));
 try{await fs.chmod(owned,0o700);const file=path.join(owned,'instrumented-local-gotrue.mjs');await fs.writeFile(file,generated,{mode:0o600});await import(pathToFileURL(file).href);}
 finally{await fs.rm(owned,{recursive:true,force:true});}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{await run();}catch(error){console.error(`FAIL auth session reuse code=${typeof error?.code==='string'?error.code:'SESSION_FIXTURE_FAILURE'}`);process.exitCode=1;}
}
