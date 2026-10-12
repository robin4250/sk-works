import {publicApiKey} from './location.mjs';
import {fetchOpenWeather,fetchWeatherKit,localParts,nextDate} from './providers.mjs';
// Resolve the actor's address and geocode on the server. The request accepts no
// address, coordinates, provider or actor override. Missing adapters fail closed.
export function createWeatherForecastHandler(deps) {
  const fetcher=deps.fetcher??fetch;
  const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
  return async req=>{
    if(req.method!=='POST')return reply({error:'POST required'},405);
    try{
      const base=deps.env('SUPABASE_URL'), key=publicApiKey(deps.env);
      const authorization=req.headers.get('authorization');
      if(!base||!key)throw new Error('Configuration unavailable');
      if(!authorization?.startsWith('Bearer '))return reply({error:'Authentication required'},401);
      const auth=await fetcher(`${base}/auth/v1/user`,{headers:{apikey:key,Authorization:authorization},signal:AbortSignal.timeout(10000),redirect:'error'});
      if(!auth.ok)return reply({error:'Authentication required'},401);
      const actor=await auth.json();if(typeof actor.id!=='string')return reply({error:'Authentication required'},401);
      const reader=req.body?.getReader();if(!reader)return reply({error:'Invalid request'},400);
      let length=0;const chunks=[];
      for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>4096){await reader.cancel();return reply({error:'Invalid request'},400);}chunks.push(value);}
      const bytes=new Uint8Array(length);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
      let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply({error:'Invalid request'},400);}
      if(!body||Array.isArray(body)||Object.keys(body).some(k=>!["day_offset","prepare_location","native_location","region_token"].includes(k))||!Number.isInteger(body.day_offset)||body.day_offset<0||body.day_offset>2)return reply({error:'Invalid request'},400);
      // These adapters must enforce user-scoped RLS and master-only persistence.
      if(!deps.resolveLocation||!deps.geocode||!deps.readProvider)throw new Error('Configuration unavailable');
      const region=await deps.resolveLocation({actorId:actor.id,authorization});
      if(!region||typeof region.address!=='string'||!region.address.trim())return reply({error:'Weather region unavailable'},422);
      const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(actor.id+"\n"+region.kind+"\n"+region.address));
      const regionToken=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,"0")).join("");
      if(body.prepare_location!==undefined&&body.prepare_location!==true)return reply({error:"Invalid request"},400);
      if(body.prepare_location===true) {
        if(body.native_location!==undefined||body.region_token!==undefined)return reply({error:"Invalid request"},400);
        return reply({address:region.address,region_kind:region.kind,region_token:regionToken});
      }
      let location;
      if(body.native_location!==undefined) {
        const native=body.native_location;
        if(body.region_token!==regionToken||!native||typeof native!=="object"||Array.isArray(native)||Object.keys(native).some(k=>!["latitude","longitude","time_zone","country_code","source"].includes(k))||native.source!=="apple_native"||!Number.isFinite(native.latitude)||Math.abs(native.latitude)>90||!Number.isFinite(native.longitude)||Math.abs(native.longitude)>180||typeof native.time_zone!=="string"||native.time_zone.length>100||typeof native.country_code!=="string"||!/^[A-Z]{2}$/.test(native.country_code))return reply({error:"Invalid location"},400);
        new Intl.DateTimeFormat("en",{timeZone:native.time_zone});
        location={latitude:native.latitude,longitude:native.longitude,timeZone:native.time_zone,countryCode:native.country_code,match:"native"};
      } else {
        if(body.region_token!==undefined)return reply({error:"Invalid request"},400);
        location=await deps.geocode(region.address);
      }
      if(!location||!["exact","native"].includes(location.match)||!location.timeZone)throw new Error('Location unavailable');
      const now=deps.now?.()??new Date(),today=localParts(now.getTime()/1000,location.timeZone).date;
      const dates=[today,nextDate(today),nextDate(nextDate(today))];
      const forecastDate=dates[body.day_offset];
      const provider=await deps.readProvider({actorId:actor.id,authorization});
      const adapter=provider==='openweather'?deps.openWeather??fetchOpenWeather:provider==='weatherkit'?deps.weatherKit??fetchWeatherKit:null;
      if(!adapter)throw new Error('Provider unavailable');
      const result=await adapter({location,date:forecastDate,env:deps.env,fetcher,now});
      if(result.forecast_date!==forecastDate||result.time_zone!==location.timeZone)throw new Error('Response mismatch');
      const radar=location.countryCode==='JP'?new URL('https://weather.yahoo.co.jp/weather/zoomradar/'):null;
      return reply({...result,base_date:today,day_offset:body.day_offset,region_kind:region.kind,location_label:region.label,country_code:location.countryCode??null,radar_url:radar?.href??null});
    }catch{
      // Never leak an API key, private key, personal address or upstream body.
      return reply({error:'Weather unavailable'},422);
    }
  };
}
