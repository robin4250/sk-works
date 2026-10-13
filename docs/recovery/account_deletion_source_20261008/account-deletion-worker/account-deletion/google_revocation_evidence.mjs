// Encrypted write-ahead evidence for a Google revocation, not an assumption of
// success. Retrying still requires real rejection of BOTH recorded credentials.
const encode=b=>btoa(String.fromCharCode(...b));
const decode=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const token=s=>typeof s==='string'&&s.length>0&&s.length<=8192&&!/[\x00-\x20\x7f]/.test(s);
export function createGoogleRevocationEvidence({rpc,keyHex,clientId}) {
 if(typeof rpc!=='function'||!/^[a-f0-9]{64}$/i.test(keyHex??'')||!token(clientId))
  throw Error('google_revocation_evidence_not_configured');
 const key=crypto.subtle.importKey('raw',Uint8Array.from(keyHex.match(/../g),v=>parseInt(v,16)),
  'AES-GCM',false,['encrypt','decrypt']);
 const binding=(job,identity)=>{
  if(!job?.id||!job.userId||!/^[a-f0-9]{64}$/.test(job.reviewedPlanDigest??'')||
     identity?.provider!=='google'||!identity.id||!identity.identity_data?.sub)
   throw Error('google_revocation_evidence_unconfirmed');
  return {jobId:job.id,userId:job.userId,identityId:identity.id,clientId,
   planDigest:job.reviewedPlanDigest,googleSubject:identity.identity_data.sub};
 };
 const aad=b=>new TextEncoder().encode(JSON.stringify(['sko-google-revocation-v1',b]));
 return {
  write:async(job,identity,tokens)=>{
   try {
    const b=binding(job,identity);
    if(!token(tokens?.refreshToken)||!token(tokens?.accessToken))throw Error('tokens');
    const iv=crypto.getRandomValues(new Uint8Array(12));
    const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad(b)},await key,
     new TextEncoder().encode(JSON.stringify({refreshToken:tokens.refreshToken,accessToken:tokens.accessToken})));
    return await rpc('write_account_deletion_google_revocation_evidence',{
     p_id:job.id,p_lease:job.leaseToken,p_identity:identity.id,p_client:clientId,
     p_envelope:{version:1,iv:encode(iv),ciphertext:encode(new Uint8Array(ciphertext))},
    })===true;
   }catch{throw Error('google_revocation_evidence_unconfirmed');}
  },
  read:async(job,identity)=>{
   try {
    const b=binding(job,identity);
    const row=await rpc('read_account_deletion_google_revocation_evidence',{
     p_id:job.id,p_lease:job.leaseToken,p_identity:identity.id,
    });
    if(row===null)return null;
    if(!row||Object.entries(b).some(([k,v])=>k!=='googleSubject'&&row[k]!==v)||
       row.envelope?.version!==1||typeof row.envelope.iv!=='string'||
       typeof row.envelope.ciphertext!=='string'||row.envelope.ciphertext.length>24000)
     throw Error('binding');
    const iv=decode(row.envelope.iv);if(iv.length!==12)throw Error('nonce');
    const plaintext=await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:aad(b)},await key,
     decode(row.envelope.ciphertext));
    const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(plaintext));
    if(!token(value.refreshToken)||!token(value.accessToken))throw Error('tokens');
    return {...b,refreshToken:value.refreshToken,accessToken:value.accessToken};
   }catch{throw Error('google_revocation_evidence_unconfirmed');}
  },
 };
}
