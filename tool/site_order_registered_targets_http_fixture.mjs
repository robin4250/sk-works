import {createRequire} from 'node:module';
import {createProjectVerifier} from '../supabase/functions/site-order-workflow/auth.mjs';
import {createOutgoingPrepareHandler} from '../supabase/functions/site-order-workflow/outgoing-handler.mjs';
const require=createRequire(import.meta.url),{createClient}=require('./site_order_edge_dependencies/node_modules/@supabase/supabase-js');

export async function verifyTargetHttpSql(db,{UA,UB,q,check,site,openNativePeer}) {
 const base='https://isolated-target-jwt.invalid';
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const jwk={...await crypto.subtle.exportKey('jwk',keys.publicKey),kid:'targets-'+crypto.randomUUID(),alg:'ES256',use:'sig'};
 const b64=b=>Buffer.from(b).toString('base64url');
 const client=createClient(base,'fixture-public-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async url=>{
  if(!String(url).endsWith('/auth/v1/.well-known/jwks.json'))throw Error('Unexpected auth URL');
  return new Response(JSON.stringify({keys:[jwk]}),{headers:{'Content-Type':'application/json'}});
 }}});
 const verify=createProjectVerifier(client,base);
 const jwt=async uid=>{
  const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);
  const now=Math.floor(Date.now()/1000),claims={iss:base+'/auth/v1',aud:'authenticated',role:'authenticated',sub:uid,session_id:sid,iat:now,exp:now+300,user_metadata:{role:'owner'}};
  const data=b64(JSON.stringify({alg:'ES256',kid:jwk.kid}))+'.'+b64(JSON.stringify(claims));
  return data+'.'+b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},keys.privateKey,new TextEncoder().encode(data)));
 };
 const definitions=await q("select jsonb_agg(pg_get_functiondef(p.oid)) v from pg_proc p where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)");
 let opened=0,closed=0;
 await db.exec(`create or replace function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),nullif(current_setting('test.jwt',true),''),'{}')::jsonb$$;
 create or replace function auth.uid()returns uuid language sql as $$select coalesce(auth.jwt()->>'sub',nullif(current_setting('test.uid',true),''))::uuid$$`);
 const handler=createOutgoingPrepareHandler({verify,connect:async()=>{
  opened++;const peer=openNativePeer?await openNativePeer():db;
  return {query:(sql,args)=>peer.query(sql,args),end:async()=>{closed++;if(openNativePeer)await peer.end();}};
 }});
 const post=async(uid,body,token)=>handler(new Request('https://function.invalid/site-order-workflow/outgoing',{
  method:'POST',headers:{authorization:'Bearer '+(token??await jwt(uid))},body:JSON.stringify(body)}));
 try {
  const command={action:'targets',site_id:site,before:null,limit:50};
  const firstResponse=await post(UA,command);check(firstResponse.status,200);const page1=(await firstResponse.json()).result;
  const secondResponse=await post(UA,{...command,before:page1.next_cursor});check(secondResponse.status,200);const page2=(await secondResponse.json()).result;
  check(page1.entries.length,50);check(page1.read_only,true);check(page2.has_more,false);
  check((await post(UB,command)).status,403);
  await db.query("update company_members set role='worker' where user_id=$1",[UA]);
  check((await post(UA,command)).status,403);
  await db.query("update company_members set role='manager' where user_id=$1",[UA]);
  await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
  check((await post(UA,command)).status,403);
  await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  const before=opened;check((await post(UA,{...command,company_id:'forged'})).status,400);check(opened,before);
  const parts=(await jwt(UA)).split('.');parts[2]=b64(new Uint8Array(64));
  check((await post(UA,command,parts.join('.'))).status,401);check(opened,before);
  check(closed,opened);check(await q("select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb v"),{});
  console.log(JSON.stringify({registered_targets_real_es256_http_sql:true,connections_closed:closed,synthetic_auth_surroundings:true,real_gotrue:false}));
  return [page1,page2];
 } finally {for(const sql of definitions)await db.exec(sql);}
}
