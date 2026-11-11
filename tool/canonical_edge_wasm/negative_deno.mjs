import {createCanonicalWasmRenderer} from './build/runtime.mjs';
const render=await createCanonicalWasmRenderer();
const cases=JSON.parse(await Deno.readTextFile(new URL('./build/cases.json',import.meta.url)));
const mutations={
 peer_seal:e=>e.seals[0].company_id=e.body.counterparty_company_id,
 missing_consent:e=>e.consents=[],
 caller_seal:e=>e.body.company_seal_enabled=true,
 unknown_terms:e=>e.body.contract_terms.version=2,
 mismatched_consent:e=>e.consents[0].seal_hash='c'.repeat(64),
};
const results=[];
for(const [name,mutate]of Object.entries(mutations)){
 const e=structuredClone(cases['order-v2']);mutate(e);let denied=false;
 try{await render(JSON.stringify(e));}catch(error){denied=String(error)==='Error: canonical_render_rejected';}
 if(!denied)throw Error('negative_case_accepted');results.push({name,denied});
}
for(const [name,value]of [['invalid_json','{"private_marker":'],['oversize',' '.repeat(2*1024*1024+1)]]){
 let denied=false;try{await render(value);}catch(error){denied=!String(error).includes('private_marker');}
 if(!denied)throw Error('negative_input_accepted');results.push({name,denied});
}
const first=render(cases['order-v2']);
let overlapDenied=false;try{await render(cases['order-v2']);}catch(error){overlapDenied=error.message==='canonical_renderer_busy';}
if(!overlapDenied||!(await first instanceof Uint8Array))throw Error('concurrent_boundary_failed');
results.push({name:'overlap',denied:overlapDenied});
console.log(JSON.stringify({runtime:Deno.version,results}));
