import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
export async function verifyHttp(db,{q,check,targetRoot,UA,UB,site}){
 const require=createRequire(pathToFileURL(path.join(targetRoot,'package.json')));
 const {createClient}=require(path.join(targetRoot,'tool/site_order_edge_dependencies/node_modules/@supabase/supabase-js'));
 const {createProjectVerifier}=await import(pathToFileURL(path.join(targetRoot,'supabase/functions/site-order-workflow/auth.mjs')));
 const {createOutgoingPrepareHandler}=await import(pathToFileURL(path.join(targetRoot,'supabase/functions/site-order-workflow/outgoing-handler.mjs')));
 const base='https://isolated-exact-eight-targets.invalid';
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',keys.publicKey),kid:crypto.randomUUID(),alg:'ES256',use:'sig'};
 const b64=b=>Buffer.from(b).toString('base64url');
 const client=createClient(base,'fixture-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
  if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('unexpected Auth URL');
  return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const verify=createProjectVerifier(client,base);
 const token=async uid=>{const sid=await q('select id v from auth.sessions where user_id=$1',[uid]);const now=Math.floor(Date.now()/1000);
  const claims={sub:uid,session_id:sid,role:'authenticated',is_anonymous:false,aud:'authenticated',iss:base+'/auth/v1',iat:now,exp:now+300,user_metadata:{role:'owner'}};
  const body=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(claims));
  return body+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(body)));
 };
 // Actual uid/jwt prefer the legacy GUCs. The pool boundary must begin empty,
 // exactly as a fresh owner connection does, rather than leaking fixture actor.
 await db.query("select set_config('request.jwt.claims','',false),set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim','',false)");
 let opened=0,closed=0;
 const handler=createOutgoingPrepareHandler({verify,connect:async()=>{
  opened++;let peer=db;
  if(process.argv[3]==='postgres'){
   const pg=(await import(process.argv[2])).default;
   const url=new URL(process.env.SKO_CONSENT_FIXTURE_URL??'');
   if(!['localhost','127.0.0.1'].includes(url.hostname)||url.pathname!=='/sko_document_consent_fixture')throw Error('disposable loopback required');
   peer=new pg.Client({connectionString:url.href});await peer.connect();
  }
  for(const key of ['request.jwt.claims','request.jwt.claim.sub','request.jwt.claim'])check((await peer.query("select coalesce(nullif(current_setting($1,true),''),'') v",[key])).rows[0].v,'');
  return {query:(s,a)=>peer.query(s,a),end:async()=>{closed++;for(const key of ['request.jwt.claims','request.jwt.claim.sub','request.jwt.claim'])check((await peer.query("select coalesce(nullif(current_setting($1,true),''),'') v",[key])).rows[0].v,'');if(peer!==db)await peer.end();}};
 }});
 const command={action:'targets',site_id:site,before:null,limit:50};
 const post=async(uid,body=command,jwt)=>handler(new Request('https://function.invalid/site-order-workflow/outgoing',{method:'POST',headers:{authorization:'Bearer '+(jwt??await token(uid))},body:JSON.stringify(body)}));
 const first=await post(UA);check(first.status,200);const page1=(await first.json()).result;
 const next=await post(UA,{...command,before:page1.next_cursor});check(next.status,200);const page2=(await next.json()).result;
 check((await post(UB)).status,403);
 await db.query("update public.company_members set role='worker' where user_id=$1",[UA]);check((await post(UA)).status,403);
 await db.query("update public.company_members set role='manager' where user_id=$1",[UA]);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");check((await post(UA)).status,403);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const before=opened;check((await post(UA,{...command,company_id:'forged'})).status,400);check(opened,before);
 const parts=(await token(UA)).split('.');parts[2]=b64(new Uint8Array(64));check((await post(UA,command,parts.join('.'))).status,401);check(opened,before);
 check(closed,opened);check(opened,5);
 console.log(JSON.stringify({exact_eight_targets_fixed_es256_http:true,connections_closed:closed,legacy_session_gucs_empty_before_after:true,real_gotrue:false}));
 return [page1,page2];
}
