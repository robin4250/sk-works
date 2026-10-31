// Disposable composition only; the frozen baseline file is never edited.
import fs from 'node:fs/promises';
import {rmSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const original=new URL('../site-order-actual-eight/verify.mjs',import.meta.url);
const source=await fs.readFile(original,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='665eddf4c7c3d410a66dccc9a6fef05607c7ac39e0dc40ec15b5a897d0d4d600')throw Error('frozen exact-eight source changed');
const anchor=" const uid='11111111-1111-4111-8111-111111111111'";
if(source.split(anchor).length!==2)throw Error('exact-eight extension anchor changed');
const temp=fileURLToPath(new URL(`../site-order-actual-eight/.targets-${randomUUID()}.mjs`,import.meta.url));
const hook=" const {verifyTargetsOnEight}=await import('../site-order-targets-exact-eight/fixture.mjs');await verifyTargetsOnEight(db,{q,check,sourceContract});\n";
try{
 await fs.writeFile(temp,source.replace(anchor,hook+anchor),{mode:0o600,flag:'wx'});
 const run=spawnSync(process.execPath,[temp,...process.argv.slice(2)],{env:process.env,stdio:'inherit'});
 if(run.error)throw run.error;if(run.status!==0)throw Error('exact-eight target composition failed');
}finally{rmSync(temp,{force:true});}
