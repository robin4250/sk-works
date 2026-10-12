import test from 'node:test';
import assert from 'node:assert/strict';
import {createWeatherForecastHandler} from './handler.mjs';
import {logWeatherFailure, logWeatherConfigurationGaps, WeatherConfigurationError} from './diagnostics.mjs';
import {geocodeRegisteredAddress} from './location.mjs';
import {fetchOpenWeather, createWeatherKitToken} from './providers.mjs';
const request = () => new Request('https://example.invalid', {method:'POST',headers:{Authorization:'Bearer PRIVATE-token'},body:'{"day_offset":0}'});
const base = {env: k => ({SUPABASE_URL:'https://example.invalid', SUPABASE_ANON_KEY:'PRIVATE-key'}[k]),
 fetcher: async () => Response.json({id:'PRIVATE-user'}),
 resolveLocation: async () => ({address:'PRIVATE-address',kind:'company',label:'company'}),
 geocode: async () => ({latitude:35,longitude:139,timeZone:'Asia/Tokyo',match:'exact'}),
 readProvider: async () => 'openweather',
 openWeather: async () => {throw Error('PRIVATE-provider-response');}};
test('diagnostic failures log only fixed stages and preserve generic client error', async () => {
 for (const [stage, override] of [
  ['region_lookup',{resolveLocation:async()=>{throw Error('PRIVATE-address');}}],
  ['geocoding',{geocode:async()=>{throw Error('PRIVATE-key');}}],
  ['provider_setting',{readProvider:async()=>{throw Error('PRIVATE-user');}}],
  ['forecast_fetch',{}],
  ['response_validation',{openWeather:async()=>({forecast_date:'invalid',time_zone:'bad'})}],
 ]) {
  const logs=[]; const response=await createWeatherForecastHandler({...base,...override,logger:line=>logs.push(line)})(request());
  assert.deepEqual(logs,[`weather_failure:${stage}`]);
  assert.equal(response.status,422);
  assert.deepEqual(await response.json(),{error:'Weather unavailable'});
 }
});
test('missing configuration enums and timeout never contain supplied exception values', async () => {
 const logs=[];const logger=line=>logs.push(line);
 logWeatherFailure('geocoding',new WeatherConfigurationError('geocoding_key_missing'),logger);
 logWeatherFailure('geocoding',new WeatherConfigurationError('PRIVATE-secret'),logger);
 logWeatherFailure('forecast_fetch',new DOMException('PRIVATE-upstream','TimeoutError'),logger);
 logWeatherFailure('PRIVATE-address',new Error('PRIVATE-user'),logger);
 assert.deepEqual(logs,['weather_failure:geocoding_key_missing','weather_failure:geocoding','weather_failure:timeout','weather_failure:server_configuration']);
 await assert.rejects(geocodeRegisteredAddress('PRIVATE-address',{env:()=>undefined}),e=>e.code==='geocoding_provider_missing');
 await assert.rejects(geocodeRegisteredAddress('PRIVATE-address',{env:k=>k==='WEATHER_GEOCODING_PROVIDER'?'google':undefined}),e=>e.code==='geocoding_key_missing');
 const location={latitude:35,longitude:139,timeZone:'Asia/Tokyo'};
 await assert.rejects(fetchOpenWeather({location,env:()=>undefined}),e=>e.code==='openweather_key_missing');
 await assert.rejects(createWeatherKitToken(()=>undefined),e=>e.code==='weatherkit_configuration_missing');
});
test('diagnostics do not mislabel an absent address as missing provider configuration', async () => {
 const logs=[];const response=await createWeatherForecastHandler({...base,resolveLocation:async()=>({address:''}),logger:line=>logs.push(line)})(request());
 assert.deepEqual(logs,['weather_failure:region_missing']);
 assert.deepEqual(await response.json(),{error:'Weather region unavailable'});
});
test('authentication and request rejection preserve existing contracts without diagnostic data',async()=>{
 const logs=[];const handle=createWeatherForecastHandler({...base,logger:line=>logs.push(line)});
 assert.equal((await handle(new Request('https://example.invalid',{method:'POST',body:'{}'}))).status,401);
 assert.equal((await handle(new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer PRIVATE-token'},body:'{"address":"PRIVATE-address"}'}))).status,400);
 assert.deepEqual(logs,[]);
});

test('configuration presence logs only fixed missing names and never existing values', () => {
 const logs=[];
 logWeatherConfigurationGaps(k=>k==='OPENWEATHER_API_KEY'?'PRIVATE-existing-secret':undefined,line=>logs.push(line));
 assert.deepEqual(logs,[
  'weather_configuration_missing:geocoding_key',
  'weather_configuration_missing:weatherkit_team',
  'weather_configuration_missing:weatherkit_service',
  'weather_configuration_missing:weatherkit_key_id',
  'weather_configuration_missing:weatherkit_private_key',
 ]);
 assert.ok(logs.every(line=>!line.includes('PRIVATE')));
 const present=[];logWeatherConfigurationGaps(()=> 'PRIVATE-value',line=>present.push(line));
 assert.deepEqual(present,[]);
});
test('presence checks wait for authenticated actor region and preserve error response',async()=>{
 const logs=[];const handler=createWeatherForecastHandler({...base,geocodeConfigurationDiagnostics:true,
  resolveLocation:async()=>{throw Error('PRIVATE-user');},logger:line=>logs.push(line)});
 assert.equal((await handler(request())).status,422);
 assert.deepEqual(logs,['weather_failure:region_lookup']);
});
