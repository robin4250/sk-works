// Dedicated synthetic HTTP/Auth adapter only, never a production server.
// Document RPCs below execute unchanged candidate SQL on the same Native DB
// whose list projection is returned to the actual Supabase Dart/UI test.
import fs from 'node:fs/promises';import http from 'node:http';import path from 'node:path';import{pathToFileURL}from'node:url';
const url=process.env.SKO_DOCUMENT_ADMIN_FIXTURE_URL;
const u=new URL(url);if(u.hostname!=='127.0.0.1'||u.pathname!=='/sko_document_admin_fixture'||u.search||u.hash){throw Error('dedicated fixture only');}
const pg=await import(pathToFileURL(path.resolve(process.argv[2])));const Client=pg.Client??pg.default.Client;
const uid=n=>`70000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=uid(1),actor=uid(4),target=uid(6),sid=uid(30),token='synthetic-native-http-only';
async function connect(){const c=new Client({connectionString:url});await c.connect();return c;}
async function rpc(action,data){
 const c=await connect();try{
  await c.query("select set_config('fixture.uid',$1,false),set_config('request.jwt.claims',$2,false)",[actor,JSON.stringify({sub:actor,session_id:sid,role:'authenticated',is_anonymous:false})]);
  await c.query('set role authenticated');
  return(await c.query('select public.worker_document_admin_self_correction($1,$2::jsonb) value',[action,JSON.stringify(data)])).rows[0].value;
 }finally{await c.end();}
}
const server=http.createServer(async(req,res)=>{
 try{
  if(req.headers.authorization!==`Bearer ${token}`){res.writeHead(401,{'content-type':'application/json'});res.end(JSON.stringify({code:'42501',message:'fixture token required'}));return;}
  if(req.method==='GET'&&req.url==='/fixture-context'){
   const c=await connect();let projection;try{
    // Exact purpose of this integration: the list omits updated_by and
    // template_version_id, while inspect/full CAS use the genuine complete row.
    projection=(await c.query('select to_jsonb(q) value from(select id,company_id,worker_id,requirement_id,status,expires_at,original_verified,attachment_path,attachment_paths,notes,updated_at from public.worker_document_statuses where id=$1)q',[target])).rows[0].value;
   }finally{await c.end();}
   // Match PostgREST's JSON representation, not node-pg Date object UTC text.
   for(const key of ['updated_at']){if(projection[key] instanceof Date){projection[key]=projection[key].toISOString();}}
   res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({projection,company,actor,target}));return;
  }
  if(req.method!=='POST'||req.url!=='/rest/v1/rpc/worker_document_admin_self_correction'){res.writeHead(404);res.end();return;}
  let body='';for await(const chunk of req){body+=chunk;if(body.length>65536){throw Error('fixture body too large');}}
  const payload=JSON.parse(body);
  const result=await rpc(payload.p_action,payload.p_data);
  res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(result));
 }catch(error){res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({code:error.code??'fixture_error',message:error.message,details:null,hint:null}));}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
await fs.writeFile(process.env.SKO_DOCUMENT_NATIVE_HTTP_CONTEXT,JSON.stringify({url:`http://127.0.0.1:${server.address().port}`,token,company,actor,target}));
console.log('Native fixture HTTP ready; synthetic Auth, genuine candidate document SQL');
