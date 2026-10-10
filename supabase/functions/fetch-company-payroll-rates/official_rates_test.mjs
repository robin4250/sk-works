// Run: node --experimental-strip-types --test supabase/functions/fetch-company-payroll-rates/official_rates_test.mjs
// Fixture: relevant official HTML sections fetched 2026-10-10; URLs are SOURCES.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fetchOfficialRates,fetchOfficialDocument,parseHealth,parseGeneralRate,parseEmployment,parsePension,verifyAnnualIndex,SOURCES,PREFECTURES} from './official_rates.ts';
const fixture=JSON.parse(readFileSync(new URL('./official_rates_fixture.json',import.meta.url),'utf8'));
const now=new Date('2026-10-10T00:00:00Z');
const scope={insurer:'kyokai',prefecture:'東京都',employment_business:'construction'};
const response=html=>new Response(html,{headers:{'content-type':'text/html; charset=UTF-8'}});
const mock=(data=fixture,visited=[])=>async url=>{ visited.push(url); const key=Object.keys(SOURCES).find(k=>SOURCES[k]===url); assert.ok(key); return response(data[key]); };

test('official 47-prefecture table selects current column, including fullwidth decimals',()=>{
 const actual=parseHealth(fixture.health,2026);
 assert.equal(actual.size,47); assert.deepEqual([...actual.keys()],PREFECTURES);
 const expected=[10.28,9.85,9.51,10.10,10.01,9.75,9.50,9.52,9.82,9.68,9.67,9.73,9.85,9.92,9.21,9.59,9.70,9.71,9.55,9.63,9.80,9.61,9.93,9.77,9.88,9.89,10.13,10.12,9.91,10.06,9.86,9.94,10.05,9.78,10.15,10.24,10.02,9.98,10.05,10.11,10.55,10.06,10.08,10.08,9.77,10.13,9.44].map(x=>Math.round(x*1000000));
 assert.deepEqual([...actual.values()],expected);
 assert.throws(()=>parseHealth(fixture.health.replace('北海道</p>','東京都</p>'),2026));
 assert.throws(()=>parseHealth(fixture.health,2027));
 assert.throws(()=>parseHealth(fixture.health.replaceAll('令和8年度','令和7年度'),2026));
});
test('general employee care/child excludes voluntary continuation and separates remittance months',()=>{
 assert.equal(parseGeneralRate(fixture.care,2026,3),1620000);
 assert.equal(parseGeneralRate(fixture.child,2026,4),230000);
 assert.throws(()=>parseGeneralRate(fixture.care,2026,4));
 assert.throws(()=>parseGeneralRate(fixture.child,2026,3));
 assert.throws(()=>parseGeneralRate(fixture.child.replace('5月納付分','４月納付分'),2026,4));
});
test('employment all three business classes retain unequal employer share',()=>{
 assert.deepEqual(parseEmployment(fixture.employment,2026),{
  general:{employee:500000,employer:850000,total:1350000},
  agriculture_forestry_fisheries_sake:{employee:600000,employer:950000,total:1550000},
  construction:{employee:600000,employer:1050000,total:1650000},
 });
 assert.throws(()=>parseEmployment(fixture.employment.replace('16.5/1,000','16.6/1,000'),2026));
 assert.throws(()=>parseEmployment(fixture.employment,2027));
 assert.throws(()=>parseEmployment(fixture.employment.replaceAll('/1,000','/100'),2026));
});
test('pension reads official fixed rate, annual indexes require matching year',()=>{
 assert.equal(parsePension(fixture.pension),18300000);
 assert.throws(()=>parsePension('18.3%'));
 verifyAnnualIndex(fixture.healthIndex,2026,'health');
 verifyAnnualIndex(fixture.employmentIndex,2026,'employment');
 assert.throws(()=>verifyAnnualIndex(fixture.employmentIndex,2027,'employment'));
 verifyAnnualIndex(fixture.employmentIndex+'令和９年度の雇用保険料率',2026,'employment');
});
test('fetch produces five candidates with source hashes and no company mutations',async()=>{
 const before=JSON.stringify(scope); const visited=[];
 const result=await fetchOfficialRates(scope,{now,fetcher:mock(fixture,visited)});
 assert.equal(JSON.stringify(scope),before); assert.equal(visited.length,7);
 assert.equal(result.rates.length,5); assert.deepEqual(result.warnings,[]);
 assert.equal(result.checkedAt,now.toISOString());
 const health=result.rates.find(r=>r.kind==='health_insurance');
 assert.equal(health.total,9850000); assert.equal(health.employee,4925000);
 assert.equal(health.insuranceMonth,'2026-03-01'); assert.equal(health.paymentMonth,'2026-04-01');
 assert.equal(health.source.document_hash,createHash('sha256').update(fixture.health).digest('hex'));
 assert.equal(health.source.applicability.effective_insurance_month,'2026-03-01');
 assert.equal(result.rates.find(r=>r.kind==='employment_insurance').paymentMonth,null);
});
test('union, other and unconfigured never fetch/apply kyokai sources',async()=>{
 for(const insurer of ['union','other','unconfigured']){
  const visited=[];const result=await fetchOfficialRates({...scope,insurer,prefecture:null},{now,fetcher:mock(fixture,visited)});
  assert.deepEqual(result.rates.map(r=>r.kind),['pension_insurance','employment_insurance']);
  assert.equal(result.warnings.length,1);assert.equal(visited.length,3);
  assert.ok(!visited.some(u=>u.includes('kyoukaikenpo')));
 }
});
test('unsupported year, company conditions and stale official index reject before publication',async()=>{
 for(const date of ['2025-10-01','2026-03-01','2027-01-01'])await assert.rejects(()=>fetchOfficialRates(scope,{now:new Date(date),fetcher:mock()}));
 for(const invalid of [{...scope,prefecture:null},{...scope,employment_business:null},{...scope,employment_business:'toString'},{...scope,insurer:'invalid'}])await assert.rejects(()=>fetchOfficialRates(invalid,{now,fetcher:mock()}));
 await assert.rejects(()=>fetchOfficialRates(scope,{now,fetcher:mock({...fixture,employmentIndex:'令和7年度の雇用保険料率'})}));
 await assert.rejects(()=>fetchOfficialRates(scope,{now,fetcher:async()=>{throw new Error('offline');}}));
});
test('source allowlist, external redirect, wrong MIME, oversized and missing response reject',async()=>{
 await assert.rejects(()=>fetchOfficialDocument('https://example.com',mock()));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>new Response(null,{status:302,headers:{location:'https://example.com/'}})));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>new Response(null,{status:302,headers:{location:'http://www.kyoukaikenpo.or.jp/about/business/insurance_rate/rate_prefectures/r08/'}})));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>new Response('bad',{status:500})));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>new Response('pdf',{headers:{'content-type':'application/pdf'}})));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>response('x'.repeat(750001))));
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async()=>new Response('small',{headers:{'content-type':'text/html','content-length':'750001'}})));
});
test('safe canonical redirect and timeout work without following arbitrary paths',async()=>{
 let calls=0;
 const doc=await fetchOfficialDocument(SOURCES.care,async()=>++calls===1?new Response(null,{status:301,headers:{location:'index.html'}}):response(fixture.care));
 assert.equal(calls,2);assert.equal(doc.html,fixture.care);
 await assert.rejects(()=>fetchOfficialDocument(SOURCES.health,async(_,options)=>new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new Error('timeout')))),5));
});
