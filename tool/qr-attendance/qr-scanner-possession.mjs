// Internal-only request-scoped adapter. initializeVerifiedSession is a trusted
// server callback, never a request body or user_metadata authority.
import {createPublicKey,verify} from 'node:crypto';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
export function scannerRegistrationSigningBytes(value){
 if(!['id','company','actor','session','device','nonce'].every(k=>typeof value?.[k]==='string'&&uuid.test(value[k])) ||
  !/^302a300506032b6570032100[a-f0-9]{64}$/.test(value.keyHex)||
  !Number.isSafeInteger(value.createdMs)||!Number.isSafeInteger(value.expiresMs)||
  value.expiresMs<=value.createdMs||value.expiresMs-value.createdMs>90000)throw Error('invalid scanner registration challenge');
 return Buffer.from(JSON.stringify(['sko.qr.scanner.register.key-possession.v1',value.id,value.company,value.actor,
  value.session,value.device,value.keyHex,value.nonce,value.createdMs,value.expiresMs]));
}
export function createScannerRegistrationPossessionAdapter({pool,initializeVerifiedSession}){
 if(typeof pool?.connect!=='function'||typeof initializeVerifiedSession!=='function')throw TypeError('trusted request pool required');
 return {async complete({challengeId,signature,reauthenticationProof}){
  if(typeof challengeId!=='string'||!uuid.test(challengeId)||!Buffer.isBuffer(signature)||signature.length!==64||
   typeof reauthenticationProof!=='string'||reauthenticationProof.length<1||reauthenticationProof.length>4096)throw Error('scanner registration rejected');
  const frozenSignature=Buffer.from(signature);const client=await pool.connect();let started=false,discard=false;
  try{
   await client.query('begin isolation level serializable');started=true;
   await client.query("set local lock_timeout='2s';set local statement_timeout='5s';set local idle_in_transaction_session_timeout='5s'");
   const principal=await initializeVerifiedSession(client);
   const raw=(await client.query('select qr_attendance_private.load_scanner_key_challenge($1) as challenge',[challengeId])).rows[0]?.challenge;
   // Scalar copy must not follow an adapter-owned mutable response across awaits.
   const c=raw&&{id:raw.id,company:raw.company,actor:raw.actor,session:raw.session,device:raw.device,keyHex:raw.keyHex,
    nonce:raw.nonce,createdMs:raw.createdMs,expiresMs:raw.expiresMs,databaseNowMs:raw.databaseNowMs};
   if(!c||c.id!==challengeId||c.actor!==principal?.actor||c.session!==principal?.session||
    !Number.isSafeInteger(c.databaseNowMs)||c.databaseNowMs<c.createdMs||c.databaseNowMs>=c.expiresMs)throw Error('scanner registration rejected');
   const bytes=scannerRegistrationSigningBytes(c),key=createPublicKey({key:Buffer.from(c.keyHex,'hex'),format:'der',type:'spki'});
   if(key.asymmetricKeyType!=='ed25519'||!verify(null,bytes,key,frozenSignature))throw Error('scanner registration rejected');
   const result=(await client.query('select qr_attendance_private.register_own_scanner_with_proof($1,$2,$3,$4) as device',
    [c.company,c.device,c.keyHex,reauthenticationProof])).rows[0]?.device;
   if(result!==c.device)throw Error('scanner registration rejected');
   await client.query('select qr_attendance_private.consume_scanner_key_challenge($1)',[challengeId]);
   await client.query('commit');started=false;return {deviceId:c.device};
  }catch(error){if(started){try{await client.query('rollback');}catch{discard=true;client.release(true);}}throw error;}
  finally{if(!discard)client.release();}
 }};
}
