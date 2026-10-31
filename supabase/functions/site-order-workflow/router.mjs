// Supabase paths are prefixed by the function name. Preserve '/' for the
// existing local/Wasm verification entry; other unknown paths are not commands.
export function createSiteOrderRouter({workflow,outgoing}){
 return req=>{
  const path=new URL(req.url).pathname.replace(/\/+$/,'')||'/';
  if(path==='/site-order-workflow/outgoing'||path==='/functions/v1/site-order-workflow/outgoing')return outgoing(req);
  if(path==='/'||path==='/site-order-workflow'||path==='/functions/v1/site-order-workflow')return workflow(req);
  return new Response(JSON.stringify({error:'not_found'}),{status:404,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 };
}
