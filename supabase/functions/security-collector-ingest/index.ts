import {createSecurityCollectorHandler} from './handler.mjs';
const baseUrl=Deno.env.get('SUPABASE_URL');
let serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const serviceKeyName=Deno.env.get('SKO_COLLECTOR_SERVICE_KEY_NAME');
if(serviceKeyName){
 try{if(!/^[A-Za-z0-9_-]{1,64}$/.test(serviceKeyName))throw new Error();serviceKey=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')??'{}')[serviceKeyName];}
 catch{throw new Error('Invalid named collector service credential');}
}
let keys;
try{keys=JSON.parse(Deno.env.get('SKO_COLLECTOR_ACTIVE_KEYS_JSON')??'[]');}
catch{throw new Error('Invalid collector key configuration');}
const enabled=()=>Deno.env.get('SKO_COLLECTOR_ENABLED')==='true';
const handler=createSecurityCollectorHandler({baseUrl,serviceKey,keys,enabled});
Deno.serve(handler);
