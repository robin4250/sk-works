import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
export async function checkHttp(db,{uid,other,cid,report}){
 const url=new URL(process.env.SKO_INCIDENT_POSTGREST_URL);
 if(url.origin!=='http://127.0.0.1:3000')throw Error('Disposable loopback PostgREST required');
 const secret='synthetic-incident-fixture-secret-at-least-32-characters';
 await db.exec(`create table private.fixture_masters(id uuid primary key);insert into private.fixture_masters values('${uid}'),('${other}');
 create or replace function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid$$;
 create or replace function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.fixture_masters where id=auth.uid())$$;
 create or replace function private.account_access_allowed() returns boolean language sql stable as $$select true$$;
 notify pgrst,'reload schema';`);
 const token=(sub,extra={},key=secret)=>{
  const header=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
  const payload=Buffer.from(JSON.stringify({role:'authenticated',sub,exp:Math.floor(Date.now()/1000)+120,...extra})).toString('base64url');
  return `${header}.${payload}.${createHmac('sha256',key).update(`${header}.${payload}`).digest('base64url')}`;
 };
 const call=async(auth,body=null)=>{
  const response=await fetch(new URL(body?'/rpc/save_master_security_incident':'/rpc/master_security_incidents',url),{method:'POST',headers:{'content-type':'application/json',...(auth?{authorization:`Bearer ${auth}`}:{})},body:JSON.stringify(body??{})});
  return {status:response.status,json:await response.json()};
 };
 let ready=false;
 for(let i=0;i<30;i++){try{if((await call(token(uid))).status===200){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,1000));}
 assert.equal(ready,true,'real PostgREST schema ready');
 assert.equal((await call()).status,403);
 assert.equal((await call(token(uid,{exp:1}))).status,401);
 assert.equal((await call(token(uid,{},'wrong-synthetic-signing-secret-32-chars'))).status,401);
 assert.equal((await call(token(crypto.randomUUID()))).status,400);
 const own=await call(token(uid));assert.equal(own.status,200);assert.ok(own.json.incidents.length>=1);
 const otherResult=await call(token(other));assert.equal(otherResult.status,200);assert.deepEqual(otherResult.json.incidents,[]);
 const record={...report,incident_id:crypto.randomUUID()};const body={p_record:record,p_record_version:1};
 assert.equal((await call(token(uid),body)).status,200);assert.equal((await call(token(uid),body)).status,200);
 assert.equal((await call(token(other),body)).status,400);
 const n=await db.query('select count(*)::int n from private.security_incident_notification_outbox where incident_id=$1',[record.incident_id]);assert.equal(n.rows[0].n,1);
 console.log('real HTTP JWT boundary passed: anonymous, expiry, signature, non-master, own-company, cross-company save, one notification');
}
