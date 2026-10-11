import test from 'node:test';
import assert from 'node:assert/strict';
import {createRateFetchHandler} from './handler.ts';
const company='12345678-1234-1234-1234-123456789abc';
const actor='22222222-2222-2222-2222-222222222222';
const scope={version:4,value:{insurer:'kyokai',prefecture:'東京都',employment_business:'construction'}};
const input={company_id:company,insurance_month:'2026-10-01',payroll_month:'2026-10-01',payment_month:'2026-11-01'};
const now=new Date('2026-10-10T00:00:00Z');
const official={rates:[{kind:'employment_insurance',total:1650000,employee:600000,employer:1050000,insuranceMonth:'2026-04-01',paymentMonth:null,source:{url:'https://jsite.mhlw.go.jp/yamagata-roudoukyoku/koyouhoken-20260316.html',publisher:'厚生労働省 山形労働局',document_hash:'a'.repeat(64),applicability:{effective_insurance_month:'2026-04-01',fiscal_year:'2026'}}}],checkedAt:now.toISOString(),year:2026,warnings:[]};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
const request=(body=input,headers={authorization:'Bearer user-token'})=>new Request('https://example.test/fetch-company-payroll-rates',{method:'POST',headers,body:typeof body==='string'?body:JSON.stringify(body)});
function setup(options={}){
 const calls=[];let reads=0;let sourceCalls=0;
 const env=name=>({SUPABASE_URL:'https://project.supabase.co',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'sb_publishable_public'}),SUPABASE_SECRET_KEYS:JSON.stringify({default:'sb_secret_private'})})[name];
 const handler=createRateFetchHandler({env:options.env??env,now:()=>now,
  fetchRates:async(actualScope,params)=>{sourceCalls++;assert.deepEqual(actualScope,scope.value);assert.equal(params.now,now);if(options.sourceFailure)throw new Error('upstream sensitive body');return options.official??official;},
  fetcher:async(url,init)=>{
   calls.push({url,init});
   assert.ok(!/apply|save_company|payroll_statements/.test(url),'fetch never applies current settings');
   if(url.endsWith('/auth/v1/user')){assert.equal(init.headers.Authorization,'Bearer user-token');return json(options.user??{id:actor},options.authStatus??200);}
   if(url.endsWith('/rpc/read_company_payroll_rates')){assert.equal(init.headers.apikey,'sb_publishable_public');assert.equal(init.headers.Authorization,'Bearer user-token');assert.deepEqual(JSON.parse(init.body),{p_company_id:company});return json((reads++===0?options.initial:options.latest)??{can_edit:true,company_scope:scope},options.readStatus??200);}
   if(url.endsWith('/rpc/publish_official_payroll_rate_candidates'))return json({ok:true},options.publishStatus??200);
   assert.fail(`Unexpected request ${url}`);
  }});
 return {handler,calls,sourceCalls:()=>sourceCalls};
}
const publications=calls=>calls.filter(c=>c.url.endsWith('/rpc/publish_official_payroll_rate_candidates'));

test('POST and authenticated actor are mandatory, no service publication',async()=>{
 const state=setup();assert.equal((await state.handler(new Request('https://example.test'))).status,405);
 assert.equal((await state.handler(request(input,{}))).status,401);
 for(const options of [{authStatus:401},{user:{id:null}}]){const s=setup(options);assert.equal((await s.handler(request())).status,401);assert.equal(publications(s.calls).length,0);assert.equal(s.sourceCalls(),0);}
});
test('viewer and missing company scope cannot initiate official retrieval',async()=>{
 for(const [initial,status] of [[{can_edit:false,company_scope:scope},403],[{can_edit:true,company_scope:null},400],[{can_edit:true,company_scope:{...scope,version:0}},400]]){
  const state=setup({initial});assert.equal((await state.handler(request())).status,status);assert.equal(state.sourceCalls(),0);assert.equal(publications(state.calls).length,0);
 }
});
test('invalid, oversized and non-object inputs never read company or publish',async()=>{
 for(const body of ['{','null','[]','x'.repeat(2049),{...input,company_id:'-'.repeat(36)}]){
  const state=setup();assert.equal((await state.handler(request(body))).status,400);assert.equal(state.calls.length,1);assert.equal(state.sourceCalls(),0);
 }
});
test('all company month choices required; future or inconsistent months fail',async()=>{
 const bad=[{...input,insurance_month:'2026-11-01'},{...input,payroll_month:'2026-07-01'},{...input,payment_month:'2026-12-01'},{...input,payment_month:'2026-09-01'},{...input,payment_month:undefined}];
 for(const body of bad){const s=setup();assert.ok((await s.handler(request(body))).status>=400);assert.equal(s.sourceCalls(),0);assert.equal(publications(s.calls).length,0);}
});
test('company scope version changes or edit permission removal prevent service publication',async()=>{
 for(const latest of [{can_edit:true,company_scope:{...scope,version:5}},{can_edit:false,company_scope:scope},{can_edit:true,company_scope:null}]){
  const state=setup({latest});assert.equal((await state.handler(request())).status,409);assert.equal(state.sourceCalls(),1);assert.equal(publications(state.calls).length,0);
 }
});
test('official fetch/parse failure and empty result preserve current settings',async()=>{
 for(const options of [{sourceFailure:true},{official:{...official,rates:[]}}]){
  const state=setup(options);const result=await state.handler(request());assert.equal(result.status,422);assert.equal(publications(state.calls).length,0);assert.ok(!(await result.text()).includes('sensitive'));
 }
});
test('old application months cannot reuse new fiscal-year employment rates',async()=>{
 const state=setup();const result=await state.handler(request({...input,insurance_month:'2026-01-01',payroll_month:'2026-01-01',payment_month:'2026-02-01'}));assert.equal(result.status,422);assert.equal(publications(state.calls).length,0);
});
test('successful retrieval publishes candidates only, user month mapping replaces source remittance',async()=>{
 const data={...official,rates:[{...official.rates[0],kind:'health_insurance',total:9850000,employee:4925000,employer:4925000,insuranceMonth:'2026-03-01',paymentMonth:'2026-04-01'}]};
 const state=setup({official:data});const result=await state.handler(request());assert.equal(result.status,200);assert.deepEqual(await result.json(),{ok:true,checked_at:official.checkedAt,warnings:[]});
 assert.equal(state.calls.length,4);const [publication]=publications(state.calls);assert.ok(publication);assert.equal(publication.init.headers.apikey,'sb_secret_private');assert.equal(publication.init.headers.Authorization,undefined);
 const body=JSON.parse(publication.init.body);assert.equal(body.p_actor_id,actor);assert.equal(body.p_scope_version,4);assert.equal(body.p_company_id,company);
 assert.equal(body.p_values[0].insurance_month,'2026-10-01');assert.equal(body.p_values[0].payroll_month,'2026-10-01');assert.equal(body.p_values[0].payment_month,'2026-11-01');
 assert.equal(body.p_values[0].source.applicability.scope_version,'4');assert.equal(body.p_values[0].source.applicability.prefecture,'東京都');
 assert.equal(body.p_values[0].employee,4925000);
});
test('publication failure never reports success or leaks internal information',async()=>{
 const state=setup({publishStatus:500});const result=await state.handler(request());assert.equal(result.status,422);assert.equal(publications(state.calls).length,1);const body=await result.text();assert.ok(!body.includes('sb_secret'));assert.ok(!body.includes('Candidate publication'));
});
test('legacy service key uses bearer server credential and malformed env is hidden',async()=>{
 const env=name=>({SUPABASE_URL:'https://project.supabase.co',SUPABASE_PUBLISHABLE_KEYS:'{"default":"sb_publishable_public"}',SUPABASE_SERVICE_ROLE_KEY:'legacy-service-token'})[name];
 const state=setup({env});assert.equal((await state.handler(request())).status,200);assert.equal(publications(state.calls)[0].init.headers.Authorization,'Bearer legacy-service-token');
 const broken=setup({env:name=>name==='SUPABASE_URL'?'https://project.supabase.co':'{broken'});assert.equal((await broken.handler(request())).status,422);assert.equal(publications(broken.calls).length,0);
});
