import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {resolve} from 'node:path';
import {createCanonicalSiteOrderRenderer} from './site_order_canonical_renderer.mjs';
const dart=process.env.SKO_CANONICAL_DART;
if(!dart)throw Error('Actual Dart renderer executable required');
const render=await createCanonicalSiteOrderRenderer({dartExecutable:dart,repositoryRoot:process.cwd()});
const cases=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-cases.json','utf8'));
for(const [name,evidence] of Object.entries(cases))test(`actual server renderer ${name}`,async()=>{
 const bytes=await render(evidence);assert.ok(bytes.length>10000);
 if(process.env.SKO_CANONICAL_PDF_OUTPUT_DIR){const folder=resolve(process.env.SKO_CANONICAL_PDF_OUTPUT_DIR);await fs.mkdir(folder,{recursive:true});await fs.writeFile(resolve(folder,`server-${name}.pdf`),bytes);}
});
for(const [name,alter] of Object.entries({
 'peer seal':e=>{e.seals[0].company_id=e.body.counterparty_company_id;},
 'missing consent':e=>{e.consents=[];},
 'caller seal':e=>{e.body.company_seal_enabled=true;},
 'unknown terms':e=>{e.body.contract_terms.version=2;},
 'mismatched seal consent':e=>{e.consents[0].seal_hash='c'.repeat(64);},
}))test(`reject ${name} without leaking payload`,async()=>{
 const e=structuredClone(cases['order-v2']);alter(e);
 await assert.rejects(()=>render(e),error=>error.message==='canonical_render_rejected');
});
