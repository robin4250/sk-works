// Default-OFF internal composition. This is not a public/retrying endpoint.
import {createPublicKey,verify} from 'node:crypto';
import {scannerRegistrationSigningBytes} from './qr-scanner-possession.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const keyPattern=/^302a300506032b6570032100[0-9a-f]{64}$/;
const deny=()=>Error('scanner registration result unavailable; reconcile original request');
export function createRecoverableScannerRegistrationAdapter({enabled=false,pool,initializeVerifiedSession}) {
 if(typeof pool?.connect!=='function'||typeof initializeVerifiedSession!=='function')throw TypeError('trusted request pool required');
 let attempted=false;
 async function execute(mode,input) {
  if(!enabled||attempted)throw deny();
  let challengeId,companyId,deviceId,keyHex,proof,signature;
  try {
   challengeId=input?.challengeId;
   if(!uuid.test(challengeId??''))throw deny();
   if(mode==='complete'){
    proof=input?.reauthenticationProof;signature=input?.signature;
    if(typeof proof!=='string'||proof.length<1||proof.length>4096||!Buffer.isBuffer(signature)||signature.length!==64)throw deny();
    signature=Buffer.from(signature);
   } else {
    companyId=input?.companyId;deviceId=input?.deviceId;keyHex=input?.keyHex;
    if(!uuid.test(companyId??'')||!uuid.test(deviceId??'')||typeof keyHex!=='string'||!keyPattern.test(keyHex))throw deny();
   }
  }catch{throw deny();}
  attempted=true;let client,started=false,discard=false;
  try {
   client=await pool.connect();await client.query('begin isolation level serializable');started=true;
   await client.query("set local lock_timeout='2s';set local statement_timeout='5s';set local idle_in_transaction_session_timeout='5s'");
   const principal=await initializeVerifiedSession(client),actor=principal?.actor,session=principal?.session;
   if(!uuid.test(actor??'')||!uuid.test(session??''))throw deny();
   let raw;
   if(mode==='complete'){
    const c=(await client.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[challengeId])).rows[0]?.challenge;
    // Snapshot before any later database await; the SQL wrapper loads it again.
    const challenge=c&&Object.fromEntries(['id','company','actor','session','device','keyHex','nonce','createdMs','expiresMs','databaseNowMs'].map(k=>[k,c[k]]));
    if(!challenge||challenge.id!==challengeId||challenge.actor!==actor||challenge.session!==session||
      !Number.isSafeInteger(challenge.databaseNowMs)||challenge.databaseNowMs<challenge.createdMs||challenge.databaseNowMs>=challenge.expiresMs)throw deny();
    const signingBytes=scannerRegistrationSigningBytes(challenge),key=createPublicKey({key:Buffer.from(challenge.keyHex,'hex'),format:'der',type:'spki'});
    if(key.asymmetricKeyType!=='ed25519'||!verify(null,signingBytes,key,signature))throw deny();
    companyId=challenge.company;deviceId=challenge.device;keyHex=challenge.keyHex;
    raw=(await client.query('select qr_attendance_private.complete_own_scanner_key_registration($1,$2) as receipt',[challengeId,proof])).rows[0]?.receipt;
   } else raw=(await client.query('select qr_attendance_private.read_own_scanner_key_registration($1,$2,$3,$4) as receipt',[challengeId,companyId,deviceId,keyHex])).rows[0]?.receipt;
   let receipt=null;
   if(raw!==null){
    const value={challengeId:raw?.challengeId,deviceId:raw?.deviceId,registrationEventId:raw?.registrationEventId};
    if(value.challengeId!==challengeId||value.deviceId!==deviceId||typeof value.registrationEventId!=='string'||
      !/^[1-9][0-9]{0,18}$/.test(value.registrationEventId)||BigInt(value.registrationEventId)>9223372036854775807n||
      raw?.companyId!==companyId||raw?.actor!==actor||raw?.session!==session||raw?.keyHex!==keyHex)throw deny();
    receipt=value;
   } else if(mode==='complete')throw deny();
   await client.query('commit');started=false;
   return mode==='complete'?{deviceId}:receipt;
  }catch{
   if(client&&started){try{await client.query('rollback');}catch{discard=true;}}
   throw deny();
  }finally{if(client)client.release(discard);}
 }
 return {complete:input=>execute('complete',input),read:input=>execute('read',input)};
}
