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
      for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>512){await reader.cancel();return reply({error:'Invalid request'},400);}chunks.push(value);}
      const bytes=new Uint8Array(length);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
      let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply({error:'Invalid request'},400);}
      if(!body||Array.isArray(body)||Object.keys(body).some(k=>k!=='day_offset')||!Number.isInteger(body.day_offset)||body.day_offset<0||body.day_offset>2)return reply({error:'Invalid request'},400);
      // These adapters must enforce user-scoped RLS and master-only persistence.
      if(!deps.resolveLocation||!deps.geocode||!deps.readProvider)throw new Error('Configuration unavailable');
      const region=await deps.resolveLocation({actorId:actor.id,authorization});
      if(!region||typeof region.address!=='string'||!region.address.trim())return reply({error:'Weather region unavailable'},422);
      const location=await deps.geocode(region.address);
      if(!location||location.match!=='exact'||!location.timeZone)throw new Error('Location unavailable');
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
