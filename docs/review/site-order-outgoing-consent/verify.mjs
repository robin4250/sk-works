// Frozen public-source baseline plus this new source-only purpose.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=process.env.SKO_EXACT_EIGHT_SOURCE_ROOT;
if(!root||!path.isAbsolute(root))throw Error('frozen exact-eight source root required');
const sourcePath=path.join(root,'docs/review/site-order-actual-eight/verify.mjs');
const source=await fs.readFile(sourcePath,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='378a717761b75903c184eab1fea23b9674248f8bd6298f01896dc01c2b0d808b')throw Error('frozen exact-eight source changed');
const anchor=" const uid='11111111-1111-4111-8111-111111111111'";
if(source.split(anchor).length!==2)throw Error('frozen extension anchor changed');
const fixture=pathToFileURL(fileURLToPath(new URL('./fixture.mjs',import.meta.url))).href;
const temp=path.join(root,'docs/review/site-order-actual-eight',`.consent-${randomUUID()}.mjs`);
try{
 await fs.writeFile(temp,source.replace(anchor,` const {verifyConsent}=await import(${JSON.stringify(fixture)});await verifyConsent(db,{q,check,sourceContract});\n`+anchor),{mode:0o600,flag:'wx'});
 const run=spawnSync(process.execPath,[temp,...process.argv.slice(2)],{env:process.env,stdio:'inherit'});
 if(run.error)throw run.error;if(run.status!==0)throw Error('exact-eight consent composition failed');
}finally{await fs.rm(temp,{force:true});}
