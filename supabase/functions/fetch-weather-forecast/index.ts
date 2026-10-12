import {createWeatherForecastHandler} from './handler.mjs';
import {publicApiKey,createUserReader,resolveWeatherAddress,geocodeRegisteredAddress} from './location.mjs';

const env=(name:string)=>Deno.env.get(name);
const readFor=(authorization:string)=>createUserReader({base:env('SUPABASE_URL'),key:publicApiKey(env),authorization});
Deno.serve(createWeatherForecastHandler({
 env,
 geocodeConfigurationDiagnostics:true,
 resolveLocation:({actorId,authorization}:{actorId:string,authorization:string})=>resolveWeatherAddress({actorId,read:readFor(authorization)}),
 geocode:(address:string)=>geocodeRegisteredAddress(address,{env}),
 readProvider:({authorization}:{authorization:string})=>readFor(authorization)('rpc/current_weather_provider',{}),
}));
