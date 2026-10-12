import {WeatherConfigurationError} from './diagnostics.mjs';
export function publicApiKey(env) {
 const raw=env('SUPABASE_PUBLISHABLE_KEYS');
 if(raw){const value=JSON.parse(raw).default;if(typeof value==='string'&&value)return value;}
 const value=env('SUPABASE_ANON_KEY');if(!value)throw Error('Weather server configuration unavailable');return value;
}
// All reads use the verified user's bearer token, never service_role.
export function createUserReader({base,key,authorization,fetcher=fetch}) {
 return async(path,body)=>{
  const r=await fetcher(`${base}/rest/v1/${path}`,{method:body===undefined?'GET':'POST',headers:{apikey:key,Authorization:authorization,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000),redirect:'error'});
  if(!r.ok)throw Error('Weather source unavailable');return await r.json();
 };
}
export async function resolveWeatherAddress({actorId,read,now=new Date()}) {
 const rows=await read(`company_members?select=company_id,role&user_id=eq.${encodeURIComponent(actorId)}&limit=2`);
 if(!Array.isArray(rows)||rows.length!==1)throw Error('Weather company unavailable');
 const companyId=rows[0].company_id;
 const companies=await read(`companies?select=address&id=eq.${encodeURIComponent(companyId)}&limit=1`);
 if(!Array.isArray(companies)||companies.length!==1)throw Error('Weather company unavailable');
 const make=(kind,address)=>({kind,address,label:kind});
 if(['owner','admin'].includes(rows[0].role))return make('company',companies[0].address);
 const profile=await read('rpc/current_worker_personnel_profile',{});
 if(profile===null||!profile.address?.trim())return make('company',companies[0].address);
 const workers=await read(`workers?select=id&company_id=eq.${encodeURIComponent(companyId)}&user_id=eq.${encodeURIComponent(actorId)}&limit=2`);
 if(!Array.isArray(workers)||workers.length!==1||profile.worker_id!==workers[0].id)throw Error('Weather worker unavailable');
 // No ensure_current_user_worker: weather must not create an employee record.
 const events=await read(`attendance_verifications?select=id,event_type,confirmed_at,source_clock_in_id,site_id,route_assignment_id&company_id=eq.${encodeURIComponent(companyId)}&worker_id=eq.${encodeURIComponent(workers[0].id)}&order=confirmed_at.desc&limit=200`);
 if(!Array.isArray(events)||events.length===200)throw Error('Weather attendance unavailable');
 const valid=events.filter(e=>Number.isFinite(Date.parse(e.confirmed_at))&&Date.parse(e.confirmed_at)<=now.getTime());
 // Require a recent start; an old unresolved clock-in is ambiguous, never home.
 const closed=new Set(valid.filter(e=>e.event_type==='clock_out'&&e.source_clock_in_id).map(e=>e.source_clock_in_id));
 const legacy=valid.filter(e=>e.event_type==='clock_out'&&!e.source_clock_in_id).map(e=>Date.parse(e.confirmed_at));
 const end=legacy.length?Math.max(...legacy):-Infinity;
 const active=valid.filter(e=>e.event_type==='clock_in'&&!closed.has(e.id)&&Date.parse(e.confirmed_at)>end);
 if(active.length===0)return make('home',profile.address);
 if(active.length!==1||now.getTime()-Date.parse(active[0].confirmed_at)>48*3600000||active[0].route_assignment_id||!active[0].site_id)throw Error('Weather current site unavailable');
 const sites=await read(`sites?select=address&id=eq.${encodeURIComponent(active[0].site_id)}&company_id=eq.${encodeURIComponent(companyId)}&limit=1`);
 if(!Array.isArray(sites)||sites.length!==1)throw Error('Weather site unavailable');
 return make('site',sites[0].address);
}
export async function geocodeRegisteredAddress(address,{env,fetcher=fetch,now=new Date()}) {
 // This adapter is explicitly opt-in. No account/product is enrolled by code.
 const key=env('WEATHER_GEOCODING_API_KEY');
 if(env('WEATHER_GEOCODING_PROVIDER')!=='google')throw new WeatherConfigurationError('geocoding_provider_missing');
 if(!key)throw new WeatherConfigurationError('geocoding_key_missing');
 const get=async url=>{const r=await fetcher(url,{signal:AbortSignal.timeout(10000),redirect:'error'});if(!r.ok)throw Error('Weather geocoding unavailable');return await r.json();};
 const url=new URL('https://maps.googleapis.com/maps/api/geocode/json');url.searchParams.set('address',address);url.searchParams.set('key',key);
 const data=await get(url);
 if(data.status!=='OK'||data.results?.length!==1||data.results[0].partial_match||data.results[0].geometry?.location_type!=='ROOFTOP')throw Error('Weather address match unavailable');
 const row=data.results[0],lat=row.geometry.location.lat,lon=row.geometry.location.lng;
 if(!Number.isFinite(lat)||Math.abs(lat)>90||!Number.isFinite(lon)||Math.abs(lon)>180)throw Error('Weather coordinates unavailable');
 const zone=new URL('https://maps.googleapis.com/maps/api/timezone/json');zone.searchParams.set('location',`${lat},${lon}`);zone.searchParams.set('timestamp',String(Math.floor(now.getTime()/1000)));zone.searchParams.set('key',key);
 const timezone=await get(zone);if(timezone.status!=='OK'||!timezone.timeZoneId)throw Error('Weather timezone unavailable');
 new Intl.DateTimeFormat('en',{timeZone:timezone.timeZoneId});
 return {latitude:lat,longitude:lon,timeZone:timezone.timeZoneId,match:'exact',countryCode:row.address_components?.find(c=>c.types.includes('country'))?.short_name??null};
}
