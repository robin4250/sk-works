// Internal, one request only. Not an endpoint or proof of JWT verification.
// initializeVerifiedSession must establish authoritative transaction-local claims.
import {createHash,randomBytes} from 'node:crypto';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export function createScannerRegistrationProofIssuer({pool,initializeVerifiedSession}) {
 if(typeof pool?.connect!=='function'||typeof initializeVerifiedSession!=='function')throw TypeError('trusted request pool required');
 let attempted=false;
 return {async issue({challengeId,password}) {
  const fail=()=>Error('scanner proof unavailable; reconcile before retry');
  if(attempted||typeof challengeId!=='string'||!uuid.test(challengeId)||typeof password!=='string'||password.length>1024)throw fail();
  attempted=true;let client,started=false,discard=false;
  try {
   client=await pool.connect();await client.query('begin isolation level serializable');started=true;
   await client.query("set local lock_timeout='2s';set local statement_timeout='5s';set local idle_in_transaction_session_timeout='5s'");
   const principal=await initializeVerifiedSession(client);
   const c=(await client.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[challengeId])).rows[0]?.challenge;
   if(c?.id!==challengeId||c?.actor!==principal?.actor||c?.session!==principal?.session)throw fail();
   const proof=randomBytes(32).toString('hex'),hash=createHash('sha256').update(proof).digest('hex');
   const expires=(await client.query('select qr_attendance_private.issue_registration_proof($1,$2,$3) as expires_at',[challengeId,password,hash])).rows[0]?.expires_at;
   if(expires!==null&&!(expires instanceof Date)&&typeof expires!=='string')throw fail();
   if(expires!==null&&!Number.isFinite(new Date(expires).getTime()))throw fail();
   // A wrong-password NULL is a successful transaction: commit its counters.
   await client.query('commit');started=false;
   return expires===null?{accepted:false}:{accepted:true,proof,expiresAt:new Date(expires).toISOString()};
  } catch {
   if(client&&started){try{await client.query('rollback');}catch{discard=true;}}
   throw fail();
  } finally {if(client)client.release(discard);}
 }};
}
