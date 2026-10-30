import {createCanonicalEdgeRenderer} from './build/edge_adapter.mjs';
const render=await createCanonicalEdgeRenderer();
const cases=JSON.parse(await Deno.readTextFile(new URL('./build/cases.json',import.meta.url)));
const evidence=cases['order-v2'],before=JSON.stringify(evidence);
const pdf=await render(evidence);
if(!(pdf instanceof Uint8Array)||new TextDecoder().decode(pdf.slice(0,5))!=='%PDF-')throw Error('actual_pdf_required');
if(before!==JSON.stringify(evidence))throw Error('evidence_mutated');
for(const invalid of [null,[],JSON.stringify(evidence),{}, {...evidence,consents:[]}]) {
 let refused=false;try{await render(invalid);}catch(e){refused=e.message==='canonical_render_rejected'&&!('cause' in e);}
 if(!refused)throw Error('fixed_rejection_required');
}
if('skoCanonicalPdfRender' in globalThis)throw Error('export_not_private');
console.log('PASS actual private Edge renderer port, bytes, unchanged evidence, five rejected inputs');
