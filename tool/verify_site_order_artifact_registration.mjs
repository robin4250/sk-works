// Reuse the exact protected canonical fixture without changing its source pin.
// Only a private temporary module receives this additional review hook.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';

if(process.env.SKO_SITE_ORDER_ARTIFACT_REGISTRATION_HOOK!=='contract-v1') {
 throw Error('Fixed isolated artifact registration hook required');
}
const root=fileURLToPath(new URL('../',import.meta.url));
const manifest=JSON.parse(await fs.readFile(new URL('./fixtures/trade_reciprocal_gate/source_manifest.json',import.meta.url),'utf8'));
for(const entry of manifest.files) {
 const bytes=await fs.readFile(path.join(root,entry.path));
 const actual=createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`),bytes])).digest('hex');
 if(actual!==entry.sha)throw Error('Exact canonical fixture source differs: '+entry.path);
}
const sourcePath=new URL('./verify_trade_document_bound_seal_consent.mjs',import.meta.url);
const source=await fs.readFile(sourcePath,'utf8');
const anchor=" console.log('PASS '+n+' bound consent checks;";
if(source.split(anchor).length!==2)throw Error('Canonical completion anchor changed');
const hook=" await (await import('./site_order_artifact_registration_fixture.mjs')).verifySiteOrderArtifactRegistration(db,{id,A,B,C,UA,UB,UV,UC,actor,q,prepare,preview,decide,confirmedTerms});\n";
const temp=fileURLToPath(new URL(`./.site-order-artifact-fixture-${randomUUID()}.mjs`,import.meta.url));
try {
 await fs.writeFile(temp,source.replace(anchor,hook+anchor),{flag:'wx',mode:0o600});
 console.log(JSON.stringify({canonical_source_files_verified:manifest.files.length,
   original_harness_changed:false,temporary_hook:true}));
 const outcome=spawnSync(process.execPath,[temp,...process.argv.slice(2)],
   {cwd:root,env:process.env,stdio:'inherit'});
 if(outcome.error)throw outcome.error;
 if(outcome.status!==0)throw Error('Artifact fixture child failed: '+(outcome.status??outcome.signal));
} finally { await fs.rm(temp,{force:true}); }
