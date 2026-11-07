const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const {stripTypeScriptTypes}=require('node:module');
const source=fs.readFileSync(path.join(__dirname,'../supabase/functions/create-employee-invite/index.ts'),'utf8');
const code=stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm,''));
const actor='11111111-1111-1111-1111-111111111111';
const company='22222222-2222-2222-2222-222222222222';
async function request(memberships,{membershipStatus=200, worker=false}={}) {
 let handler;const calls=[];
 const fetch=async(url,init={})=>{
  calls.push({url,method:init.method||'GET'});
  if(url.endsWith('/auth/v1/user'))return Response.json({id:actor});
  if(url.includes('/rest/v1/company_members?'))return Response.json(memberships,{status:membershipStatus});
  if(url.includes('/rest/v1/workers?'))return Response.json([]);
  throw Error('Unexpected downstream request: '+url);
 };
 vm.runInNewContext(code,{TextEncoder,TextDecoder,Response,Request,AbortSignal,crypto,fetch,
  Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://fixture.invalid':k==='SUPABASE_SERVICE_ROLE_KEY'?'fixture-key':undefined},serve:fn=>{handler=fn;}},
  serverAccountAccess:()=>async()=>true,createDeletionInspection:()=>async()=>null,serverAccountActivity:()=>({})});
 const response=await handler(new Request('https://fixture.invalid/invite',{method:'POST',headers:{authorization:'Bearer fixture-token','content-type':'application/json'},body:JSON.stringify(worker?{workerId:'33333333-3333-3333-3333-333333333333'}:{})}));
 return {status:response.status,body:await response.json(),calls};
}
function noEffects(r){assert.ok(r.calls.every(c=>c.method==='GET'));assert.ok(r.calls.every(c=>!c.url.includes('/auth/v1/admin/')));}
test('two memberships stop before worker lookup or account creation',async()=>{const r=await request([{company_id:company,role:'owner'},{company_id:actor,role:'owner'}],{worker:true});assert.equal(r.status,409);assert.equal(r.calls.length,2);assert.match(r.calls[1].url,/limit=2/);noEffects(r);});
test('reversing memberships cannot choose a different company',async()=>{const r=await request([{company_id:actor,role:'viewer'},{company_id:company,role:'owner'}],{worker:true});assert.equal(r.status,409);assert.equal(r.calls.length,2);noEffects(r);});
test('no membership keeps refusal',async()=>{const r=await request([]);assert.equal(r.status,403);noEffects(r);});
test('malformed single membership stops safely',async()=>{for(const value of [null,{}, {company_id:'not-a-uuid',role:'owner'},{company_id:company,role:'unknown'}]){const r=await request([value]);assert.equal(r.status,503);assert.equal(r.calls.length,2);noEffects(r);}});
test('membership lookup failure cannot create an invite',async()=>{const r=await request({error:'unavailable'},{membershipStatus:503});assert.equal(r.status,500);noEffects(r);});
test('single owner preserves exact-company worker lookup',async()=>{const r=await request([{company_id:company,role:'owner'}],{worker:true});assert.equal(r.status,404);assert.ok(r.calls[2].url.includes('company_id=eq.'+company));noEffects(r);});
test('single ordinary employee cannot send initial worker registration',async()=>{const r=await request([{company_id:company,role:'viewer'}],{worker:true});assert.equal(r.status,403);assert.equal(r.calls.length,2);noEffects(r);});
