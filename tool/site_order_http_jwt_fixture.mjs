import {createRequire} from 'node:module';
import {createProjectVerifier} from '../supabase/functions/site-order-workflow/auth.mjs';
import {createSiteOrderHandler} from '../supabase/functions/site-order-workflow/handler.mjs';
const require=createRequire(import.meta.url),{createClient}=require('./site_order_edge_dependencies/node_modules/@supabase/supabase-js');
export async function verifySiteOrderHttpJwt(db,{id,UA,UB,UC,q,check,second,queued,renderer,openNativePeer,processReply=false,refusal=null}){
 const base='https://isolated-sko-jwt.invalid';
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',keys.publicKey),kid:'isolated-pg-'+crypto.randomUUID(),alg:'ES256',use:'sig'};
 const b64=b=>Buffer.from(b).toString('base64url');
 const client=createClient(base,'fixture-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
 if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('Unexpected auth URL');
 return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const verify=createProjectVerifier(client,base);
 const jwt=async uid=>{const sid=await q('select id v from auth.sessions where user_id=$1',[uid]);
 const now=Math.floor(Date.now()/1000),body={iss:base+'/auth/v1',aud:'authenticated',role:'authenticated',sub:uid,session_id:sid,iat:now,exp:now+300};
 const data=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(body));
 return data+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(data)));};
 const definitions=await q("select jsonb_agg(pg_get_functiondef(p.oid)) v from pg_proc p where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)");
 let connections=0,ends=0;
 // Disposable auth functions read the SAME transaction-local key as production.
 // The fallback preserves the surrounding unchanged canonical fixture context.
 await db.exec(`create or replace function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),nullif(current_setting('test.jwt',true),''),'{}')::jsonb$$;
 create or replace function auth.uid()returns uuid language sql as $$select coalesce(auth.jwt()->>'sub',nullif(current_setting('test.uid',true),''))::uuid$$`);
 const handler=createSiteOrderHandler({verify,connect:async()=>{connections++;const peer=openNativePeer?await openNativePeer():db;return {query:peer.query.bind(peer),end:async()=>{ends++;if(openNativePeer)await peer.end();}};},render:renderer});
 const post=async(uid,body)=>handler(new Request('https://function.invalid',{method:'POST',headers:{authorization:'Bearer '+await jwt(uid)},body:JSON.stringify(body)}));
 try{
  for(const uid of [UA,UB]){
   const r=await post(uid,{action:'status',package_id:second.package_id});check(r.status,200);check((await r.json()).result.reply_original_registered,true);
   const pdf=await post(uid,{action:'archive',package_id:second.package_id,kind:'acceptance'});check(pdf.status,200);check(new TextDecoder().decode((await pdf.arrayBuffer()).slice(0,5)),'%PDF-');
  }
  check((await post(UC,{action:'status',package_id:second.package_id})).status,403);
  check((await post(UB,{action:'register_original',job_id:queued.job_id})).status,403);
  await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  const rendered=await post(UB,{action:'register_original',job_id:queued.job_id});check(rendered.status,200);check((await rendered.json()).result.job_id,queued.job_id);
  if(refusal){
   const decision=await post(UB,{action:'refuse',package_id:refusal.package_id,request_id:refusal.request_id,confirmed:true});check(decision.status,200);check((await decision.json()).result.status,'rejected');
   const detail=await post(UA,{action:'detail',package_id:refusal.package_id});check(detail.status,200);check((await detail.json()).result.rejected,true);
  }
  if(processReply){const sent=await post(UB,{action:'process_reply',package_id:second.package_id});check(sent.status,200);check((await sent.json()).result.status,'recipient_stored');}
  const bad=await jwt(UB),parts=bad.split('.');parts[2]=b64(new Uint8Array(64));const before=connections;
  const rejected=await handler(new Request('https://function.invalid',{method:'POST',headers:{authorization:'Bearer '+parts.join('.')},body:JSON.stringify({action:'status',package_id:second.package_id})}));
  check(rejected.status,401);check(connections,before);check(ends,connections);
  check(await q("select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb v"),{});
 }finally{for(const sql of definitions)await db.exec(sql);}
}
