// Disposable official GoTrue/PG bridge only. Never a hosted transport or route.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createNativeApplePasswordSuccessorBroker} from './native_apple_successor_broker.mjs';
const dbURL='postgresql://postgres:root@127.0.0.1:5432/postgres';
const origin='https://ztktgquxvcxcjxtluspu.supabase.co';
if(process.env.SKO_APPLE_LIFECYCLE_ADMIN_URL!==dbURL)throw Error('disposable_fixture_only');
const input=JSON.parse(readFileSync(0,'utf8'));
const target=new URL(input.fixtureURL);
if(target.protocol!=='http:'||target.hostname!=='127.0.0.1'||target.username||target.password||target.pathname!=='/'||target.search||target.hash)throw Error('loopback_fixture_only');
const {default:pg}=await import(process.env.SKO_APPLE_BROKER_NATIVE_DRIVER);
const pool=new pg.Pool({connectionString:dbURL,max:2});
let deliveries=0,delivered=null,passwordCalls=0,appleCalls=0;
const trace=[];
const instrumentedPool={connect:async()=>{const db=await pool.connect();return {release:()=>db.release(),query:async(sql,args)=>{
 const op=['begin_password_successor','reserve_password_successor','claim_successor_attempt','complete_with_successor','hold_apple_native_subject'].find(x=>sql.includes(x));
 try{const result=await db.query(sql,args);if(op)trace.push({op,returned:!!result.rows[0]?.r});
 if(op==='reserve_password_successor'&&!result.rows[0]?.r){
  const diagnostic=await db.query(`select c is not null context_present,
    (c-array['account_allowed','primary_password_configured','session_id'])=(i.snapshot-'session_id') snapshot_same,
    c->'primary_credential_version'=i.snapshot->'primary_credential_version' credential_same,
    c->'profile_version'=i.snapshot->'profile_version' profile_same,
    c->'memberships'=i.snapshot->'memberships' memberships_same,
    c->'google_identities'=i.snapshot->'google_identities' google_same,
    s.created_at>=i.created_at session_fresh,
    a.created_at>=i.created_at amr_fresh,a.authentication_method='password' amr_password
   from apple_native_enrollment_private.password_successor_intents i
   left join auth.sessions s on s.id=$2
   left join auth.mfa_amr_claims a on a.session_id=s.id and a.authentication_method='password'
   cross join lateral(select apple_native_enrollment_private.context(i.actor_id,s.id) c) x
   where i.id=$1`,[args[0],args[3]]);
  trace.push({diagnostic:diagnostic.rows[0]??null});
 }
 return result;}
 catch(e){trace.push({op:op??'transaction',code:/^[A-Z0-9]{5}$/.test(e.code??'')?e.code:'unknown'});throw e;}
 }}}};
const fetcher=async(raw,options)=>{
 const u=new URL(raw);assert.equal(u.origin,origin);assert.ok(u.pathname.startsWith('/auth/v1/'));
 if(u.searchParams.get('grant_type')==='password')passwordCalls++;
 if(u.searchParams.get('grant_type')==='id_token')appleCalls++;
 return fetch(new URL(u.pathname+u.search,target),options);
};
try{
 const broker=createNativeApplePasswordSuccessorBroker({enabled:true,nativeOnlyReviewed:true,successorReviewed:true,
  passwordSuccessorReviewed:true,databaseReviewed:true,deliveryReviewed:true,audiences:['com.skworks.skWorks'],
  baseUrl:origin,publicKey:'sb_publishable_fixture',authTimeoutMs:10000},{pool:instrumentedPool,fetcher,
  resolveKey:async kid=>{assert.equal(kid,input.jwk.kid);return input.jwk;},
  deliverVerifiedSuccessor:async credential=>{deliveries++;delivered=credential;return true;}});
 const args={exactBearer:input.originalBearer,password:input.password,idToken:input.idToken,rawNonce:input.rawNonce};
 if(input.expected==='success'){
  const result=await broker(args);assert.equal(result.linked,true);assert.equal(result.user_id,input.actor);
  assert.equal(deliveries,1);assert.equal(delivered.user_id,input.actor);assert.equal(result.session_id,delivered.session_id);
  assert.equal(passwordCalls,1);assert.equal(appleCalls,1);
  const ledger=await pool.query('select r.status,s.original_session_id,s.successor_session_id,i.original_session_id intent_sid from apple_native_enrollment_private.requests r join apple_native_enrollment_private.successor_receipts s using(request_id) join apple_native_enrollment_private.password_successor_intents i using(request_id)');
  assert.equal(ledger.rows.length,1);assert.equal(ledger.rows[0].status,'completed');
  assert.equal(ledger.rows[0].intent_sid,input.originalSID);assert.equal(ledger.rows[0].successor_session_id,result.session_id);
  assert.notEqual(ledger.rows[0].original_session_id,input.originalSID,'password SID is distinct and separately recorded');
  let refresh=delivered.refresh_token;
  for(let n=0;n<2;n++){
   const response=await fetcher(origin+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({refresh_token:refresh})});
   assert.equal(response.status,200);const next=await response.json();assert.equal(next.user.id,input.actor);assert.ok(next.refresh_token);refresh=next.refresh_token;
  }
  await assert.rejects(broker(args));assert.equal(appleCalls,1);assert.equal(deliveries,1);
 }else{
  assert.equal(input.expected,'wrong-password');await assert.rejects(broker(args));await assert.rejects(broker(args));
  assert.equal(passwordCalls,1);assert.equal(appleCalls,0);assert.equal(deliveries,0);
  const row=(await pool.query('select count(*)::int n from apple_native_enrollment_private.requests')).rows[0];assert.equal(row.n,0);
  const response=await fetcher(origin+'/auth/v1/user',{headers:{Authorization:'Bearer '+input.originalBearer}});assert.equal(response.status,200);
 }
 process.stdout.write(JSON.stringify({verified:true,case:input.expected,deliveries,passwordCalls,appleCalls}));
}catch{
 // Never include Auth responses, SQL parameters or credentials in CI output.
 process.stderr.write(JSON.stringify({error:'isolated_password_successor_broker_failed',passwordCalls,appleCalls,trace})+'\n');process.exitCode=1;
}finally{delivered=null;await pool.end();}
