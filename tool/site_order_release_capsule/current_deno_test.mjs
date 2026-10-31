// Exact staged current imports and canonical bytes only; no SQL/Auth/server proof.
const check=(value,code)=>{if(!value)throw Error(code);};
const root=new URL(`file://${Deno.args[0].replace(/\/$/,'')}/`);
const path=name=>new URL(name,root);
const {serveSiteOrderWorkflow}=await import(path('supabase/functions/site-order-workflow/runtime.mjs'));
const {createSiteOrderHandler}=await import(path('supabase/functions/site-order-workflow/handler.mjs'));
const {createOutgoingPrepareHandler}=await import(path('supabase/functions/site-order-workflow/outgoing-handler.mjs'));
const {createSiteOrderRouter}=await import(path('supabase/functions/site-order-workflow/router.mjs'));
const {createProjectVerifier}=await import(path('supabase/functions/site-order-workflow/auth.mjs'));
const {createCanonicalEdgeRenderer}=await import(path('supabase/functions/site-order-workflow/_canonical/edge_adapter.mjs'));
check(typeof serveSiteOrderWorkflow==='function'&&typeof createProjectVerifier==='function','runtime_import');
let touched=0;
const forbidden=()=>{touched++;throw Error('external_forbidden');};
const verify=async()=>{throw Error('synthetic_denied');};
const router=createSiteOrderRouter({workflow:createSiteOrderHandler({verify,connect:forbidden,render:forbidden}),outgoing:createOutgoingPrepareHandler({verify,connect:forbidden,render:forbidden})});
let rejected=0;
for(const prefix of ['/site-order-workflow','/functions/v1/site-order-workflow']){
 for(const suffix of ['', '/outgoing']){
  const url='https://example.invalid'+prefix+suffix;
  for(const [init,status] of [[{method:'GET'},405],[{method:'POST'},401],[{method:'POST',headers:{authorization:'Bearer rejected'}},401]]){
   check((await router(new Request(url,init))).status===status,'current_rejection_boundary');rejected++;
  }
 }
}
check((await router(new Request('https://example.invalid/unknown'))).status===404,'unknown_route');
check(touched===0,'rejected_request_external_touch');
const cases=JSON.parse(await Deno.readTextFile(Deno.args[1]));
const evidence=cases['order-v2'],before=JSON.stringify(evidence);
const render=await createCanonicalEdgeRenderer();
const pdf=await render(evidence);
check(pdf instanceof Uint8Array&&new TextDecoder().decode(pdf.subarray(0,5))==='%PDF-','fixed_actual_pdf');
check(before===JSON.stringify(evidence),'synthetic_evidence_unchanged');
check(!('skoCanonicalPdfRender' in globalThis),'private_runtime_export');
console.log(JSON.stringify({runtime_transitive_imports:true,index_entrypoint_executed:false,nine_source_files_hash_pinned_by_stager:true,rejected_http_boundaries:rejected,unknown_route:true,actual_staged_pdf:true,real_jwt_or_sql:false,network_or_project_permission:false,deployed:false,production_changed:false}));
