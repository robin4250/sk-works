const reply=(data,status)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createWorkerHandler({serviceKey,enabled,createRun}){
 return async req=>{
  if(!serviceKey||req.headers.get('authorization')!=='Bearer '+serviceKey)return reply({error:'forbidden'},403);
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  if(enabled()!==true)return reply({error:'worker_disabled'},503);
  try{
   const text=await req.text();if(text.length>100)return reply({error:'invalid_request'},400);
   const p=JSON.parse(text);
   if(!p||Object.keys(p).length!==1||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(p.jobId??''))return reply({error:'invalid_request'},400);
   const result=await createRun()(p.jobId);
   return reply(result,result.status==='completed'?200:409);
  }catch{return reply({error:'worker_unavailable'},503);}
 };
}
