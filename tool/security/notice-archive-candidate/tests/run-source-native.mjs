// Reuses the exact #1494 Native harness; no original assertions are removed.
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const sha=x=>createHash('sha256').update(x).digest('hex');
const original=await readFile(new URL('./pinned-notice-native.mjs.fixture',import.meta.url),'utf8');
const install=await readFile(new URL('./pinned-notice-install.sql.fixture',import.meta.url),'utf8');
assert.equal(sha(original),'42a524c5312101707b2f1b476f9a033d47acba1865dbac27bb75c35d93912bc4');
assert.equal(sha(install),'70553f5afc9f5ae48ad1dad00d913bc4bbdd65c4a1e371c96dc8184b073e54fc');
const marker=' console.log(JSON.stringify({ok:true,postgres17:true';assert.equal(original.split(marker).length,2);
const hook=new URL('./archive-source-native-hook.mjs',import.meta.url).href;
const combined=original.replace(marker,` await (await import(${JSON.stringify(hook)})).verifyLockedSourceExport({db,a,b,claims,actor,sid,cid,collector,event,sha});\n${marker}`);
const directory=await mkdtemp(fileURLToPath(new URL('../../.archive-source-native-',import.meta.url)));
try{
 await writeFile(directory+'/install.sql.review-only',install,{mode:0o600});
 await writeFile(directory+'/verify.mjs',combined,{mode:0o600});
 const pg=fileURLToPath(new URL('../../fixture_dependencies/node_modules/pg/lib/index.js',import.meta.url));
 const result=spawnSync(process.execPath,[directory+'/verify.mjs',pg],{stdio:'inherit',env:process.env});
 if(result.status!==0)throw Error('Native source export fixture failed');
}finally{await rm(directory,{recursive:true,force:true});}
