import test from 'node:test';import assert from 'node:assert/strict';
import {normalizeForecast,fetchOpenWeather,fetchWeatherKit,createWeatherKitToken} from './providers.mjs';
import {createWeatherForecastHandler} from './handler.mjs';
const now=new Date('2026-10-12T00:00:00Z'),location={latitude:35,longitude:139,timeZone:'Asia/Tokyo',match:'exact'};
const epoch=s=>Date.parse(s)/1000;
test('region calendar date and 24h next-day boundary use exact sourced hours',()=>{
 const result=normalizeForecast({date:'2026-10-12',timeZone:'Asia/Tokyo',source:'test',now,hours:[{epoch:epoch('2026-10-11T15:00:00Z'),temperature:12,probability:.2},{epoch:epoch('2026-10-12T15:00:00Z'),temperature:13,probability:1},{epoch:epoch('2026-10-12T03:30:00Z'),temperature:99}],current:{epoch:epoch('2026-10-12T00:00:00Z'),temperature:25}});
 assert.equal(result.hours.length,9);assert.equal(result.hours[0].temperature_celsius,12);assert.equal(result.hours[8].temperature_celsius,13);assert.equal(result.hours[4].temperature_celsius,null);assert.equal(result.hours[0].precipitation_probability_percent,20);
});
test('future day never borrows current data or missing 48h forecasts',()=>{
 const r=normalizeForecast({date:'2026-10-14',timeZone:'Asia/Tokyo',source:'test',now,hours:[],current:{epoch:epoch('2026-10-12T00:00:00Z'),temperature:25}});assert.equal(r.current_temperature_celsius,null);assert.equal(r.summary_kind,'unavailable');assert.ok(r.hours.every(h=>h.temperature_celsius===null));
});
test('OpenWeather metric contract, timezone mismatch, sanitized errors',async()=>{
 let captured;const r=await fetchOpenWeather({location,date:'2026-10-12',now,env:()=> 'test-key',fetcher:async url=>{captured=new URL(url);return Response.json({timezone:'Asia/Tokyo',current:{dt:epoch('2026-10-12T00:00:00Z'),temp:18,weather:[{id:800}]},hourly:[]});}});assert.equal(captured.searchParams.get('units'),'metric');assert.equal(r.current_temperature_celsius,18);assert.equal(r.condition,'openweather:800');
 await assert.rejects(fetchOpenWeather({location,date:'2026-10-12',now,env:()=> 'test-key',fetcher:async()=>Response.json({timezone:'Europe/London'})}),/timezone mismatch/);
});
test('WeatherKit requests both datasets and preserves source chance',async()=>{
 let captured,headers;const r=await fetchWeatherKit({location,date:'2026-10-12',now,env:()=>undefined,tokenFactory:async()=> 'test-token',fetcher:async(url,options)=>{if(new URL(url).pathname.startsWith('/attribution/'))return Response.json({serviceName:'Apple Weather','logoLight@2x':'/assets/light.png','logoDark@2x':'/assets/dark.png'});captured=new URL(url);headers=options.headers;return Response.json({currentWeather:{asOf:'2026-10-12T00:00:00Z',temperature:20,conditionCode:'Clear',metadata:{attributionURL:'https://weatherkit.apple.com/legal-attribution.html'}},forecastHourly:{hours:[{forecastStart:'2026-10-11T15:00:00Z',temperature:10,precipitationChance:.4,conditionCode:'Rain'}]}});}});assert.equal(captured.searchParams.get('dataSets'),'currentWeather,forecastHourly');assert.equal(headers.Authorization,'Bearer test-token');assert.equal(r.hours[0].precipitation_probability_percent,40);assert.equal(r.attribution.name,'Apple Weather');
});
test('WeatherKit ES256 token signature and exp use server private key',async()=>{
 const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);const raw=await crypto.subtle.exportKey('pkcs8',keys.privateKey);const pem=`-----BEGIN PRIVATE KEY-----\n${Buffer.from(raw).toString('base64')}\n-----END PRIVATE KEY-----`;
 const config={WEATHERKIT_TEAM_ID:'TEAM',WEATHERKIT_SERVICE_ID:'service',WEATHERKIT_KEY_ID:'KID',WEATHERKIT_PRIVATE_KEY:pem};const token=await createWeatherKitToken(k=>config[k],now);const [h,c,s]=token.split('.');const head=JSON.parse(Buffer.from(h,'base64url')),claims=JSON.parse(Buffer.from(c,'base64url'));assert.equal(head.id,'TEAM.service');assert.equal(claims.exp-claims.iat,300);assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},keys.publicKey,Buffer.from(s,'base64url'),new TextEncoder().encode(`${h}.${c}`)),true);
});
const base={env:k=>({SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'test-public'}[k]),fetcher:async()=>Response.json({id:'actor'}),now:()=>now,resolveLocation:async()=>({address:'registered address',kind:'home',label:'Home'}),geocode:async()=>location,readProvider:async()=> 'openweather',openWeather:async({date})=>({forecast_date:date,time_zone:'Asia/Tokyo',hours:[]})};
const request=body=>new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer test-user'},body:JSON.stringify(body)});
test('gateway authenticates, rejects provider/address injection and unsupported day',async()=>{
 const handle=createWeatherForecastHandler(base);assert.equal((await handle(request({day_offset:0}))).status,200);for(const body of [{day_offset:0,address:'other person'},{day_offset:0,provider:'weatherkit'},{day_offset:3}])assert.equal((await handle(request(body))).status,400);assert.equal((await handle(new Request('https://example.invalid',{method:'POST',body:'{}'}))).status,401);
});
test('gateway rejects ambiguous geocode, unavailable adapters and mismatched response without leaks',async()=>{
 for(const override of [{geocode:async()=>({...location,match:'ambiguous'})},{resolveLocation:undefined},{openWeather:async()=>({forecast_date:'2026-10-13',time_zone:'Asia/Tokyo'})},{readProvider:async()=>{throw Error('PRIVATE-secret');}}]){const r=await createWeatherForecastHandler({...base,...override})(request({day_offset:0}));assert.equal(r.status,422);assert.ok(!(await r.text()).includes('PRIVATE-secret'));}
});

test('4day hourly contract fills supplied day2 slots without borrowing another day',async()=>{
 const r=await fetchOpenWeather({location,date:'2026-10-14',now,env:k=>k==='OPENWEATHER_HOURLY_PRODUCT'?'4day':'test-key',fetcher:async url=>new URL(url).host==='pro.openweathermap.org'?Response.json({list:[{dt:epoch('2026-10-13T15:00:00Z'),main:{temp:14},pop:.5,weather:[{id:500}]}]}):Response.json({timezone:'Asia/Tokyo',current:{temp:23},hourly:[]})});
 assert.equal(r.hours[0].temperature_celsius,14);assert.equal(r.current_temperature_celsius,null);assert.equal(r.hours[1].temperature_celsius,null);
});

test('selected-day sourced summary distinguishes forecast from stale current',()=>{
 const r=normalizeForecast({date:'2026-10-14',timeZone:'Asia/Tokyo',source:'test',now,hours:[{epoch:epoch('2026-10-14T03:00:00Z'),temperature:17,condition:'Clear'}],current:{epoch:epoch('2026-10-12T00:00:00Z'),temperature:23}});
 assert.equal(r.summary_kind,'forecast_hour');assert.equal(r.summary_hour,12);assert.equal(r.summary_temperature_celsius,17);assert.equal(r.current_temperature_celsius,null);
 const stale=normalizeForecast({date:'2026-10-12',timeZone:'Asia/Tokyo',source:'test',now,hours:[],current:{epoch:epoch('2026-10-11T00:00:00Z'),temperature:23}});assert.equal(stale.current_temperature_celsius,null);assert.equal(stale.summary_kind,'unavailable');
});
test('Yahoo radar appears only for a sourced Japanese address country',async()=>{
 for(const countryCode of ['JP','US',null]){const r=await createWeatherForecastHandler({...base,geocode:async()=>({...location,countryCode})})(request({day_offset:0}));const data=await r.json();assert.equal(data.radar_url,countryCode==='JP'?'https://weather.yahoo.co.jp/weather/zoomradar/':null);}
});
