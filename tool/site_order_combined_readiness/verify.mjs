// Compose two frozen source candidates through private temporary test copies.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {requireCompletion} from './completion.mjs';
const root=path.resolve(new URL('../../',import.meta.url).pathname);
const sourcePath=path.join(root,'tool/site_order_target_composition/verify.mjs');
const source=await fs.readFile(sourcePath,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='261db874def20e16c729a9443c68ab989c7a3638b26d7ea1a916db5d937f080d')throw Error('frozen1702 launcher changed');
const anchor='const token=randomUUID(),fixtureName=';
if(source.split(anchor).length!==2)throw Error('combined launcher anchor changed');
const helper=new URL('./fixture.mjs',import.meta.url).href;
const fixtureHook=' const {installCombinedFixture}=await import('+JSON.stringify(helper)+');const combinedSmoke=await installCombinedFixture(db,{q,check});\n';
const extra=`
const combinedLoad=" await db.exec(await read('docs/review/site-order-outgoing/source-and-prepare-observation.sql.review-only'));";
modified=replace(modified,combinedLoad,${JSON.stringify(fixtureHook)}+combinedLoad);
const combinedEnd="  console.log(JSON.stringify({consent_source_only:true";
modified=replace(modified,combinedEnd,"  await combinedSmoke({q,check,UA,UB,A,B,sid,id,claims,use});\\n"+combinedEnd);
let combinedOriginal=modified;
for(const patch of [...patches].reverse())combinedOriginal=combinedOriginal.replace(patch.after,patch.before);
if(combinedOriginal!==source||patches.length!==7)throw Error('combined exact seven fixture changes failed');
`;
// Preserve argv and the original launcher's own fixture-only engine restriction.
const temporary=path.join(root,'tool/site_order_target_composition','.combined-'+randomUUID()+'.mjs');
let created=false;
try{
 const handle=await fs.open(temporary,'wx',0o600);created=true;
 try{await handle.writeFile(source.replace(anchor,extra+anchor));}finally{await handle.close();}
 const result=spawnSync(process.execPath,[temporary,...process.argv.slice(2)],{env:process.env,encoding:'utf8',maxBuffer:16*1024*1024,timeout:12*60*1000});
 if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);
 if(result.error)throw result.error;if(result.status!==0)throw Error('combined child failed');
 requireCompletion(result.stdout);
}finally{if(created)await fs.rm(temporary,{force:true});}
