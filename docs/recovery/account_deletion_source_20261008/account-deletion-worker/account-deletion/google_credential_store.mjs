import {createGoogleIdentityRevocation} from './google_revocation.mjs';

const encode = bytes => btoa(String.fromCharCode(...bytes));
const decode = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
const context = ({userId,identityId,clientId}) =>
 new TextEncoder().encode(JSON.stringify(['sko-deletion-google-v1',userId,identityId,clientId]));

// Encryption key belongs only to the server secret store, never to the DB,
// app, request body, logs, or repository. No plaintext token is persisted.
export function createGoogleCredentialStore({rpc,keyHex,clientId,clientSecret,fetchImpl=fetch}) {
 if(typeof rpc!=='function' || typeof keyHex!=='string' || !/^[0-9a-f]{64}$/i.test(keyHex))
  throw Error('google_credential_store_not_configured');
 const key = crypto.subtle.importKey('raw',Uint8Array.from(keyHex.match(/../g),v=>parseInt(v,16)),
  'AES-GCM',false,['encrypt','decrypt']);
 const binding = value => value && typeof value.userId==='string' && value.userId &&
  typeof value.identityId==='string' && value.identityId && value.clientId===clientId;
 return {
  prepareIntake:async(user,sessionId,refreshToken)=>{
   try {
    if(!Array.isArray(user?.identities) || user.identities.length===0)throw Error('unknown_identity');
    const identities=user.identities.filter(i=>i.provider==='google');
    if(identities.length===0) {
     if(refreshToken!==undefined)throw Error('unexpected_token');
     return null;
    }
    if(identities.length!==1 || typeof refreshToken!=='string')throw Error('missing_token');
    const identity=identities[0];
    const credential={jobId:`intake:${sessionId}`,userId:user.id,identityId:identity.id,clientId,refreshToken};
    await createGoogleIdentityRevocation({clientId,clientSecret,fetchImpl,
     readCredential:async()=>credential}).inspect({id:credential.jobId,userId:user.id},identity);
    const iv=crypto.getRandomValues(new Uint8Array(12));
    const sealed=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:context(credential)},await key,
     new TextEncoder().encode(refreshToken));
    return {userId:user.id,identityId:identity.id,clientId,
     envelope:{version:1,iv:encode(iv),ciphertext:encode(new Uint8Array(sealed))}};
   }catch(_){throw Error('google_credential_unconfirmed');}
  },
  readCredential:async({jobId,userId,identityId,leaseToken})=>{
   try {
    const row=await rpc('read_account_deletion_google_credential',{
     p_id:jobId,p_lease:leaseToken,p_identity:identityId,
    });
    if(!binding(row) || row.jobId!==jobId || row.userId!==userId || row.identityId!==identityId ||
       row.envelope?.version!==1 || typeof row.envelope.iv!=='string' ||
       typeof row.envelope.ciphertext!=='string' || row.envelope.ciphertext.length>12000)
     throw Error('binding_mismatch');
    const iv=decode(row.envelope.iv);
    if(iv.length!==12)throw Error('invalid_nonce');
    const plaintext=await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:context(row)},await key,
     decode(row.envelope.ciphertext));
    return {jobId,userId,identityId,clientId,refreshToken:new TextDecoder('utf-8',{fatal:true}).decode(plaintext)};
   }catch(_){throw Error('google_credential_unconfirmed');}
  },
 };
}
