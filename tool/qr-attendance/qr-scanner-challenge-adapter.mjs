// Internal request-scoped boundary, not an endpoint or JWT verifier.
// A failed/unknown issue is reconciled with read(); never automatically reissued.
import {scannerRegistrationSigningBytes} from './qr-scanner-possession.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const denied=()=>Error('scanner challenge unavailable; reconcile original before retry');
export function createScannerRegistrationChallengeAdapter({pool,initializeVerifiedSession}) {
 if(typeof pool?.connect!=='function'||typeof initializeVerifiedSession!=='function')throw TypeError('trusted request pool required');
 let attempted=false;
 async function execute(mode,{companyId,deviceId,keyHex}) {
  if(attempted||!uuid.test(companyId??'')||!uuid.test(deviceId??'')||typeof keyHex!=='string'||!/^302a300506032b6570032100[0-9a-f]{64}$/.test(keyHex))throw denied();
  attempted=true;let client,started=false,discard=false;
  try {
   client=await pool.connect();await client.query('begin isolation level serializable');started=true;
   await client.query("set local lock_timeout='2s';set local statement_timeout='5s';set local idle_in_transaction_session_timeout='5s'");
   const principal=await initializeVerifiedSession(client),actor=principal?.actor,session=principal?.session;
   if(!uuid.test(actor??'')||!uuid.test(session??''))throw denied();
   let raw;
   if(mode==='issue') {
    const id=(await client.query('select qr_attendance_private.issue_scanner_key_challenge($1,$2,$3) as id',[companyId,deviceId,keyHex])).rows[0]?.id;
    if(!uuid.test(id??''))throw denied();
    raw=(await client.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[id])).rows[0]?.challenge;
    if(raw?.id!==id)throw denied();
   } else raw=(await client.query('select qr_attendance_private.read_own_scanner_key_challenge($1,$2,$3) as challenge',[companyId,deviceId,keyHex])).rows[0]?.challenge;
   let result=null;
   if(raw!==null) {
    // Copy all scalar fields before the awaited COMMIT; no mutable result escape.
    result={};for(const key of ['id','company','actor','session','device','keyHex','nonce','createdMs','expiresMs','databaseNowMs'])result[key]=raw?.[key];
    scannerRegistrationSigningBytes(result);
    if(result.company!==companyId||result.device!==deviceId||result.keyHex!==keyHex||result.actor!==actor||result.session!==session||
      !Number.isSafeInteger(result.databaseNowMs)||result.databaseNowMs<result.createdMs||result.databaseNowMs>=result.expiresMs)throw denied();
   } else if(mode==='issue')throw denied();
   await client.query('commit');started=false;return result;
  } catch {
   if(client&&started){try{await client.query('rollback');}catch{discard=true;}}
   throw denied();
  } finally {if(client)client.release(discard);}
 }
 return {issue:target=>execute('issue',target),read:target=>execute('read',target)};
}
