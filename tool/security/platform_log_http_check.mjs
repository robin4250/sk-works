import {createHmac} from 'node:crypto';import assert from 'node:assert/strict';
const secret='platform-fixture-only-secret-at-least-32-characters';
function jwt(claims,key=secret){const e=o=>Buffer.from(JSON.stringify(o)).toString('base64url');const b=e({alg:'HS256',typ:'JWT'})+'.'+e({exp:Math.floor(Date.now()/1000)+300,...claims});return b+'.'+createHmac('sha256',key).update(b).digest('base64url');}
export async function checkHttp(db,batch){
 const url=new URL(process.env.SKO_PLATFORM_POSTGREST_URL);if(url.hostname!=='127.0.0.1'||url.protocol!=='http:')throw Error('Disposable loopback HTTP only');
 await db.exec("notify pgrst,'reload schema'");
 const call=async(name,body,token)=>fetch(new URL(`/rpc/${name}`,url),{method:'POST',headers:{'content-type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
 let ready=false;for(let i=0;i<30;i++){const r=await call('service_ingest_platform_monitor',{p_batch:batch},jwt({role:'service_role'}));if(r.status===200){ready=true;break;}if(r.status!==404&&r.status!==503)throw Error(`HTTP setup failure ${r.status}`);await new Promise(r=>setTimeout(r,200));}assert.ok(ready,'PostgREST schema ready');
 const ordinary={role:'authenticated',sub:'22222222-2222-4222-8222-222222222222',fixture_account:true,fixture_master:false};
 for(const token of [undefined,jwt(ordinary),jwt({...ordinary,fixture_master:true,fixture_account:false}),jwt({...ordinary,fixture_master:true},'bad-signature-key'),jwt({...ordinary,fixture_master:true,exp:1})]){assert.ok([400,401,403].includes((await call('master_platform_security_monitor',{p_proof:'http-valid-proof'},token)).status));}
 assert.equal((await call('service_ingest_platform_monitor',{p_batch:batch},jwt(ordinary))).status,403);
 await db.exec("insert into private.fixture_proofs values('http-valid-proof',false)");
 const master=jwt({...ordinary,fixture_master:true});const r=await call('master_platform_security_monitor',{p_proof:'http-valid-proof'},master);assert.equal(r.status,200);const out=await r.json();assert.equal(out.source_provenance,'supabase_platform_logs');assert.equal(out.events.length,1);
 assert.ok((await call('master_platform_security_monitor',{p_proof:'http-valid-proof'},master)).status>=400);
 console.log('PASS signed HTTP JWT boundaries: anon/nonmaster/disabled/bad signature/expired/service ingest/master proof replay; fixture claims only.');
}
