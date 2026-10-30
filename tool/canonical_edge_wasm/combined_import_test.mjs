// Local composition only. No project environment, network, DB or server permission.
const check = (value, code) => { if (!value) throw Error(code); };
const root = new URL(`file://${Deno.args[0].replace(/\/$/, '')}/`);
const path = name => new URL(name, root);
const {serveSiteOrderWorkflow} = await import(path('supabase/functions/site-order-workflow/runtime.mjs'));
const {createSiteOrderHandler} = await import(path('supabase/functions/site-order-workflow/handler.mjs'));
const {createProjectVerifier} = await import(path('supabase/functions/site-order-workflow/auth.mjs'));
const {createCanonicalEdgeRenderer} = await import(path('supabase/functions/site-order-workflow/_canonical/edge_adapter.mjs'));
check(typeof serveSiteOrderWorkflow === 'function' && typeof createProjectVerifier === 'function', 'actual_runtime_import_required');
let touched = false;
const rejectExternal = () => { touched = true; throw Error('external_resource_forbidden'); };
const handler = createSiteOrderHandler({verify: async () => { throw Error('synthetic_denied'); }, connect: rejectExternal, render: rejectExternal});
check((await handler(new Request('https://example.invalid', {method: 'GET'}))).status === 405, 'method_boundary');
check((await handler(new Request('https://example.invalid', {method: 'POST'}))).status === 401, 'missing_bearer_boundary');
check((await handler(new Request('https://example.invalid', {method: 'POST', headers: {authorization: 'Bearer rejected'}}))).status === 401, 'rejected_bearer_boundary');
check(!touched, 'no_database_or_renderer_for_rejected_request');
// Only the existing synthetic immutable fixture reaches the real staged renderer.
// This is not a real JWT/admission/DB/production authorization test.
const cases = JSON.parse(await Deno.readTextFile(new URL('./synthetic-cases.json', import.meta.url)));
const evidence = cases['order-v2'], before = JSON.stringify(evidence);
const render = await createCanonicalEdgeRenderer();
const pdf = await render(evidence);
check(pdf instanceof Uint8Array && new TextDecoder().decode(pdf.subarray(0, 5)) === '%PDF-', 'actual_staged_pdf_required');
check(before === JSON.stringify(evidence), 'evidence_unchanged');
check(!('skoCanonicalPdfRender' in globalThis), 'private_runtime_export');
console.log(JSON.stringify({combined_import: true, actual_staged_pdf: true, rejected_http_boundaries: 3,
  real_jwt_or_db: false, network_or_project_environment_permission: false,
  synthetic_node_environment_only: true, deployed: false, production_changed: false}));
