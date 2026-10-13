import test from 'node:test';import assert from 'node:assert/strict';
import {resolveWeatherAddress,geocodeRegisteredAddress,createUserReader} from './location.mjs';
const now=new Date('2026-10-12T09:00:00Z');
function reader({role='worker',address='Home',events=[]}={}) {const paths=[];return {paths,read:async p=>{paths.push(p);if(p.startsWith('company_members?'))return [{company_id:'company',role}];if(p.startsWith('companies?'))return [{address:'Company'}];if(p==='rpc/current_worker_personnel_profile')return {address,worker_id:'worker'};if(p.startsWith('workers?'))return [{id:'worker'}];if(p.startsWith('attendance_verifications?'))return events;if(p.startsWith('sites?'))return [{address:'Site'}];throw Error('unexpected read');}};}
const start={id:'start',event_type:'clock_in',confirmed_at:'2026-10-12T08:00:00Z',site_id:'site',route_assignment_id:null};
test('server address policy keeps company/home/fixed active site scoped to actor',async()=>{
 for(const [options,kind] of [[{role:'admin'},'company'],[{address:''},'company'],[{},'home'],[{events:[start]},'site'],[{events:[start,{event_type:'clock_out',confirmed_at:'2026-10-12T08:30:00Z',source_clock_in_id:'start'}]},'home']]){const r=reader(options);assert.equal((await resolveWeatherAddress({actorId:'actor',read:r.read,now})).kind,kind);assert.ok(r.paths[0].includes('user_id=eq.actor'));if(kind==='site')assert.ok(r.paths.some(p=>p.startsWith('sites?')&&p.includes('company_id=eq.company')));assert.ok(!r.paths.some(p=>p.includes('ensure_current')));}
});
test('route, multiple starts, stale start and inaccessible company do not guess home/site',async()=>{
 for(const events of [[{...start,route_assignment_id:'route'}],[start,{...start,id:'other'}],[{...start,confirmed_at:'2026-10-09T00:00:00Z'}]]){const r=reader({events});await assert.rejects(resolveWeatherAddress({actorId:'actor',read:r.read,now}));assert.ok(!r.paths.some(p=>p.startsWith('sites?')));}
 await assert.rejects(resolveWeatherAddress({actorId:'actor',read:async p=>p.startsWith('company_members?')?[{company_id:'c'}]:[],now}));
});
test('geocode requires opt-in exact single rooftop and real IANA timezone',async()=>{
 const env=k=>k==='WEATHER_GEOCODING_PROVIDER'?'google':'test-key';
 const row={geometry:{location_type:'ROOFTOP',location:{lat:35,lng:139}},address_components:[{types:['country'],short_name:'JP'}]};
 const fetcher=async url=>new URL(url).pathname.includes('geocode')?Response.json({status:'OK',results:[row]}):Response.json({status:'OK',timeZoneId:'Asia/Tokyo'});
 const result=await geocodeRegisteredAddress('registered',{env,fetcher,now});assert.equal(result.timeZone,'Asia/Tokyo');assert.equal(result.countryCode,'JP');
 for(const results of [[row,row],[{...row,partial_match:true}],[{...row,geometry:{...row.geometry,location_type:'APPROXIMATE'}}],[]])await assert.rejects(geocodeRegisteredAddress('registered',{env,now,fetcher:async()=>Response.json({status:'OK',results})}));
 await assert.rejects(geocodeRegisteredAddress('registered',{env:()=>undefined,fetcher,now}));
});
test('reader propagates actor bearer and never uses service key',async()=>{
 let options;const read=createUserReader({base:'https://example.invalid',key:'public-test',authorization:'Bearer actor',fetcher:async(_,o)=>{options=o;return Response.json([]);}});await read('companies?select=address');assert.equal(options.headers.Authorization,'Bearer actor');assert.equal(options.headers.apikey,'public-test');assert.equal(options.method,'GET');
});
