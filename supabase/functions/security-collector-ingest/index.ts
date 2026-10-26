import {createSecurityCollectorHandler} from './handler.mjs';
const baseUrl=Deno.env.get('SUPABASE_URL');
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
let keys;
try{keys=JSON.parse(Deno.env.get('SKO_COLLECTOR_ACTIVE_KEYS_JSON')??'[]');}
catch{throw new Error('Invalid collector key configuration');}
const enabled=()=>Deno.env.get('SKO_COLLECTOR_ENABLED')==='true';
const handler=createSecurityCollectorHandler({baseUrl,serviceKey,keys,enabled});
Deno.serve(handler);
