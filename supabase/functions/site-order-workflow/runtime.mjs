import {createClient} from 'npm:@supabase/supabase-js@2.78.0';
import pg from 'npm:pg@8.16.3';
import {createCanonicalEdgeRenderer} from './_canonical/edge_adapter.mjs';
import {createProjectVerifier} from './auth.mjs';
import {createSiteOrderHandler} from './handler.mjs';
import {createOutgoingPrepareHandler} from './outgoing-handler.mjs';
import {createSiteOrderRouter} from './router.mjs';

export function serveSiteOrderWorkflow(runtime){
 const project=runtime.env.get('SUPABASE_URL');
 const rawKeys=runtime.env.get('SUPABASE_PUBLISHABLE_KEYS');
 const publicKey=rawKeys?JSON.parse(rawKeys).default:runtime.env.get('SUPABASE_ANON_KEY');
 const databaseUrl=runtime.env.get('SUPABASE_DB_URL');
 if(!project||!publicKey||!databaseUrl)throw Error('site_order_server_configuration');
 const url=new URL(project),dbUrl=new URL(databaseUrl);
 if(url.protocol!=='https:'||!['postgres:','postgresql:'].includes(dbUrl.protocol)
 ||dbUrl.searchParams.get('sslmode')==='disable')throw Error('site_order_server_configuration');
 for(const name of [...dbUrl.searchParams.keys()])if(name.startsWith('ssl'))dbUrl.searchParams.delete(name);
 const auth=createClient(project,publicKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:(url,options)=>fetch(url,{...options,signal:AbortSignal.timeout(10_000)})}});
 const verify=createProjectVerifier(auth,project);
 // One fixed bundled renderer; no HTTP URL/path/bytes can select assets or code.
 let rendererPromise;
 const render=async evidence=>(await(rendererPromise??=createCanonicalEdgeRenderer()))(evidence);
 const connect=async()=>{
  const client=new pg.Client({connectionString:dbUrl.href,ssl:{rejectUnauthorized:true},connectionTimeoutMillis:10_000,
   application_name:'sko-site-order-workflow',query_timeout:45_000});
  try{await client.connect();return client;}catch{await client.end().catch(()=>{});throw Error('site_order_database_unavailable');}
 };
 runtime.serve(createSiteOrderRouter({
  workflow:createSiteOrderHandler({verify,connect,render}),
  outgoing:createOutgoingPrepareHandler({verify,connect}),
 }));
}
