// Provider secrets remain on the server. No SDK or network is required by tests.
export function localParts(epochSeconds, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone, year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hourCycle:'h23'}).formatToParts(new Date(epochSeconds*1000));
  const get = type => parts.find(p=>p.type===type)?.value;
  return {date:`${get('year')}-${get('month')}-${get('day')}`,hour:Number(get('hour')),minute:Number(get('minute'))};
}
export function nextDate(date) {
  return new Date(Date.parse(`${date}T00:00:00Z`)+86400000).toISOString().slice(0,10);
}
const finite = value => typeof value==='number' && Number.isFinite(value) ? value : null;
const probability = value => finite(value)!==null && value>=0 && value<=1 ? value*100 : null;
export function normalizeForecast({date,timeZone,hours,current,source,now=new Date(),attribution=null}) {
  const today = localParts(now.getTime()/1000,timeZone).date;
  const next = nextDate(date);
  const slots = Array.from({length:9},(_,i)=>{
    const targetDate=i===8?next:date, hour=i===8?0:i*3;
    const match=hours.filter(row=>{const p=localParts(row.epoch,timeZone);return p.date===targetDate && p.hour===hour && p.minute===0;});
    const row=match.length===1?match[0]:null;
    return {hour:i*3,temperature_celsius:finite(row?.temperature),precipitation_probability_percent:probability(row?.probability),condition:row?.condition??null};
  });
  // Future days never borrow current conditions; missing fields remain unavailable.
  const summary=date===today&&Number.isFinite(current?.epoch)&&localParts(current.epoch,timeZone).date===today?current:null;
  const forecastSlot=slots.find(h=>h.hour===12&&h.temperature_celsius!==null)??slots.find(h=>h.hour<24&&h.temperature_celsius!==null);
  const summaryKind=summary?'current':forecastSlot?'forecast_hour':'unavailable';
  return {contract_version:1,forecast_date:date,time_zone:timeZone,source,checked_at:now.toISOString(),summary_kind:summaryKind,summary_hour:summary?null:forecastSlot?.hour??null,summary_temperature_celsius:summary?finite(summary.temperature):forecastSlot?.temperature_celsius??null,summary_condition:summary?.condition??forecastSlot?.condition??null,current_temperature_celsius:finite(summary?.temperature),condition:summary?.condition??null,hours:slots,attribution};
}
async function json(fetcher,url,headers={}) {
  const response=await fetcher(url,{headers,signal:AbortSignal.timeout(15000),redirect:'error'});
  if(!response.ok) throw new Error('Weather provider unavailable');
  return await response.json();
}
function coordinates(location) {
  if(!Number.isFinite(location.latitude)||Math.abs(location.latitude)>90||!Number.isFinite(location.longitude)||Math.abs(location.longitude)>180) throw new Error('Coordinates unavailable');
  new Intl.DateTimeFormat('en',{timeZone:location.timeZone});
}
export function normalizeRainApproach({date,timeZone,minutes,referenceEpoch,expiresEpoch=null,source,now=new Date()}) {
  const seconds=now.getTime()/1000;
  if(date!==localParts(seconds,timeZone).date||!Number.isFinite(referenceEpoch)||
      referenceEpoch<seconds-15*60||referenceEpoch>seconds+60||
      (expiresEpoch!==null&&(!Number.isFinite(expiresEpoch)||expiresEpoch<=seconds)))return null;
  const candidates=minutes.filter(row=>Number.isFinite(row.epoch)&&row.epoch>=seconds&&row.epoch<=seconds+3600&&
    finite(row.precipitation)!==null&&row.precipitation>0&&localParts(row.epoch,timeZone).date===date).sort((a,b)=>a.epoch-b.epoch);
  if(!candidates.length)return null;
  const earliest=candidates[0];
  if(candidates.filter(row=>row.epoch===earliest.epoch).length!==1)return null;
  const local=localParts(earliest.epoch,timeZone);
  return {forecast_at:new Date(earliest.epoch*1000).toISOString(),reference_at:new Date(referenceEpoch*1000).toISOString(),local_hour:local.hour,local_minute:local.minute,precipitation_mm_per_hour:earliest.precipitation,source};
}
export async function fetchOpenWeather({location,date,env,fetcher=fetch,now=new Date()}) {
  coordinates(location);
  const key=env('OPENWEATHER_API_KEY'); if(!key)throw new Error('Weather configuration unavailable');
  const url=new URL('https://api.openweathermap.org/data/3.0/onecall');
  for(const [k,v]of Object.entries({lat:location.latitude,lon:location.longitude,appid:key,units:'metric',lang:'ja',exclude:'daily,alerts'}))url.searchParams.set(k,String(v));
  const data=await json(fetcher,url);
  // Trust location's reviewed IANA zone, not a device timezone or guessed offset.
  if(data.timezone!==location.timeZone)throw new Error('Weather timezone mismatch');
  const condition=row=>Number.isInteger(row?.weather?.[0]?.id)?`openweather:${row.weather[0].id}`:null;
  let hourly=data.hourly;
  if(env('OPENWEATHER_HOURLY_PRODUCT')==='4day') {
    const hourlyUrl=new URL('https://pro.openweathermap.org/data/2.5/forecast/hourly');
    for(const [k,v]of Object.entries({lat:location.latitude,lon:location.longitude,appid:key,units:'metric',lang:'ja'}))hourlyUrl.searchParams.set(k,String(v));
    const extended=await json(fetcher,hourlyUrl);
    hourly=(Array.isArray(extended.list)?extended.list:[]).map(row=>({...row,temp:row.main?.temp}));
  }
  const hours=(Array.isArray(hourly)?hourly:[]).filter(row=>Number.isFinite(row.dt)).map(row=>({epoch:row.dt,temperature:row.temp,probability:row.pop,condition:condition(row)}));
  const result=normalizeForecast({date,timeZone:location.timeZone,hours,current:data.current?{epoch:data.current.dt,temperature:data.current.temp,condition:condition(data.current)}:null,source:'OpenWeather',now,attribution:{name:'OpenWeather',url:'https://openweathermap.org/'}});
  // Minute precipitation is a sourced series, not a fabricated rain approach ETA.
  const minutes=(Array.isArray(data.minutely)?data.minutely:[]).filter(row=>Number.isFinite(row.dt)).map(row=>({epoch:row.dt,precipitation:row.precipitation}));
  result.rain_approach=normalizeRainApproach({date,timeZone:location.timeZone,minutes,referenceEpoch:minutes[0]?.epoch,source:'OpenWeather',now});
  return result;
}
const b64=bytes=>btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
export async function createWeatherKitToken(env,now=new Date(),cryptoImpl=crypto) {
  const team=env('WEATHERKIT_TEAM_ID'),service=env('WEATHERKIT_SERVICE_ID'),kid=env('WEATHERKIT_KEY_ID'),pem=env('WEATHERKIT_PRIVATE_KEY');
  if(!team||!service||!kid||!pem)throw new Error('Weather configuration unavailable');
  const seconds=Math.floor(now.getTime()/1000), encoder=new TextEncoder();
  const head=b64(encoder.encode(JSON.stringify({alg:'ES256',kid,id:`${team}.${service}`})));
  const claims=b64(encoder.encode(JSON.stringify({iss:team,sub:service,iat:seconds,exp:seconds+300})));
  const raw=pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'');
  const key=await cryptoImpl.subtle.importKey('pkcs8',Uint8Array.from(atob(raw),c=>c.charCodeAt(0)),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
  const signature=await cryptoImpl.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,encoder.encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64(new Uint8Array(signature))}`;
}
export async function fetchWeatherKit({location,date,env,fetcher=fetch,now=new Date(),tokenFactory=createWeatherKitToken}) {
  coordinates(location);
  const token=await tokenFactory(env,now);
  const url=new URL(`https://weatherkit.apple.com/api/v1/weather/ja/${location.latitude}/${location.longitude}`);
  url.searchParams.set('dataSets','currentWeather,forecastHourly');url.searchParams.set('timezone',location.timeZone);
  url.searchParams.set('hourlyEnd',new Date(now.getTime()+96*3600000).toISOString());
  const data=await json(fetcher,url,{Authorization:`Bearer ${token}`});
  const hours=(Array.isArray(data.forecastHourly?.hours)?data.forecastHourly.hours:[]).filter(row=>Number.isFinite(Date.parse(row.forecastStart))).map(row=>({epoch:Date.parse(row.forecastStart)/1000,temperature:row.temperature,probability:row.precipitationChance,condition:typeof row.conditionCode==='string'?`weatherkit:${row.conditionCode}`:null}));
  const current=data.currentWeather;
  const assets=await json(fetcher,'https://weatherkit.apple.com/attribution/ja',{Authorization:`Bearer ${token}`});
  const appleUrl=value=>{if(typeof value!=='string')throw Error('Weather attribution unavailable');const url=new URL(value,'https://weatherkit.apple.com');if(url.protocol!=='https:'||url.hostname!=='weatherkit.apple.com')throw Error('Weather attribution unavailable');return url.href;};
  const attribution={name:assets.serviceName??'Apple Weather',url:appleUrl(current?.metadata?.attributionURL??data.forecastHourly?.metadata?.attributionURL),logo_light_url:appleUrl(assets['logoLight@2x']),logo_dark_url:appleUrl(assets['logoDark@2x']),trademark_required:true};
  const result=normalizeForecast({date,timeZone:location.timeZone,hours,current:current?{epoch:Date.parse(current.asOf)/1000,temperature:current.temperature,condition:typeof current.conditionCode==='string'?`weatherkit:${current.conditionCode}`:null}:null,source:'Apple Weather',now,attribution});
  result.rain_approach=null;
  // Optional next-hour data must not suppress the useful current/hourly response.
  if(date===localParts(now.getTime()/1000,location.timeZone).date&&/^[A-Z]{2}$/.test(location.countryCode??'')) {
    try {
      const availableUrl=new URL(`https://weatherkit.apple.com/api/v1/availability/${location.latitude}/${location.longitude}`);
      availableUrl.searchParams.set('country',location.countryCode);
      const available=await json(fetcher,availableUrl,{Authorization:`Bearer ${token}`});
      if(Array.isArray(available)&&available.includes('forecastNextHour')) {
        const nextUrl=new URL(url);nextUrl.searchParams.set('dataSets','forecastNextHour');nextUrl.searchParams.set('countryCode',location.countryCode);nextUrl.searchParams.delete('hourlyEnd');
        const next=await json(fetcher,nextUrl,{Authorization:`Bearer ${token}`});
        const forecast=next.forecastNextHour,meta=forecast?.metadata;
        if(meta&&meta.temporarilyUnavailable!==true&&meta.units==='m') {
          const minutes=(Array.isArray(forecast.minutes)?forecast.minutes:[]).map(row=>({epoch:Date.parse(row.startTime)/1000,precipitation:row.precipitationIntensity}));
          result.rain_approach=normalizeRainApproach({date,timeZone:location.timeZone,minutes,referenceEpoch:Date.parse(meta.readTime)/1000,expiresEpoch:Date.parse(meta.expireTime)/1000,source:'Apple Weather',now});
        }
      }
    } catch { /* Unavailable minute forecast remains null, never "no rain". */ }
  }
  return result;
}
