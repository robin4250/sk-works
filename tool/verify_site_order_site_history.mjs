// A private temporary hook composes the existing pinned harness unchanged.
import fs from 'node:fs/promises';
import {rmSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
if(process.env.SKO_SITE_ORDER_ARTIFACT_REGISTRATION_HOOK!=='contract-v1')throw Error('isolated hook required');
const manifest=JSON.parse(await fs.readFile(path.join(root,'tool/fixtures/trade_reciprocal_gate/source_manifest.json'),'utf8'));
for(const entry of manifest.files){const bytes=await fs.readFile(path.join(root,entry.path));
 if(createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`),bytes])).digest('hex')!==entry.sha)throw Error('canonical source differs: '+entry.path);}
const source=await fs.readFile(path.join(root,'tool/verify_trade_document_bound_seal_consent.mjs'),'utf8');
const anchor=" console.log('PASS '+n+' bound consent checks;";
if(source.split(anchor).length!==2)throw Error('canonical hook anchor changed');
const context='{id,A,B,C,UA,UB,UV,UC,actor,q,prepare,preview,decide,confirmedTerms,openNativePeer}';
const hook=[['site_order_artifact_registration_fixture','verifySiteOrderArtifactRegistration'],
 ['site_order_manager_adapter_fixture','verifySiteOrderManagerAdapter'],
 ['site_order_package_flow_fixture','verifySiteOrderPackageFlow'],
 ['site_order_site_history_fixture','verifySiteOrderSiteHistory']]
 .map(([file,fn])=>` await (await import('./${file}.mjs')).${fn}(db,${context});\n`).join('');
const temp=path.join(root,'tool',`.site-order-artifact-fixture-${randomUUID()}.mjs`);
try{
 await fs.writeFile(temp,source.replace(anchor,hook+anchor),{flag:'wx',mode:0o600});
 const result=spawnSync(process.execPath,[temp,...process.argv.slice(2)],{cwd:root,env:process.env,stdio:'inherit'});
 if(result.error)throw result.error;
 if(result.status!==0)throw Error('site history fixture failed: '+(result.status??result.signal));
}finally{rmSync(temp,{force:true});}
