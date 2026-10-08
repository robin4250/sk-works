// Server-only encrypted journal. Persist before the first Storage removal so
// retries use the SAME previously served URL, never a new token after deletion.
const enc=new TextEncoder();
const b64=b=>{let s='';for(let i=0;i<b.length;i+=8192)s+=String.fromCharCode(...b.subarray(i,i+8192));return btoa(s);};
const unb64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
export function createErasureEvidence({rpc,storage,keyHex,origin,fetchImpl=fetch,now=Date.now}) {
 if(typeof rpc!=='function'||!/^[a-f0-9]{64}$/i.test(keyHex??''))throw Error('erasure_evidence_not_configured');
 const base=new URL(origin);if(base.protocol!=='https:'||base.username||base.password||base.pathname!=='/'||base.search||base.hash)throw Error('invalid_storage_origin');
 const key=crypto.subtle.importKey('raw',Uint8Array.from(keyHex.match(/../g),v=>parseInt(v,16)),'AES-GCM',false,['encrypt','decrypt']);
 const ctx=j=>enc.encode(JSON.stringify(['sko-erasure-evidence-v1',j.id,j.userId,j.reviewedPlanDigest]));
 const load=async j=>{
  const row=await rpc('read_account_deletion_erasure_evidence',{p_id:j.id,p_lease:j.leaseToken});
  if(row===null)return null;
  if(row?.version!==1||typeof row.iv!=='string'||typeof row.ciphertext!=='string'||row.ciphertext.length>2000000)throw Error('invalid_erasure_evidence');
  const plaintext=await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(row.iv),additionalData:ctx(j)},await key,unb64(row.ciphertext));
  const data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(plaintext));
  if(data.jobId!==j.id||data.userId!==j.userId||data.planDigest!==j.reviewedPlanDigest||data.inventoryComplete!==true||!Array.isArray(data.files))throw Error('invalid_erasure_evidence');
  return data;
 };
 const save=async(j,data)=>{
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:ctx(j)},await key,enc.encode(JSON.stringify(data)));
  if(await rpc('write_account_deletion_erasure_evidence',{p_id:j.id,p_lease:j.leaseToken,p_envelope:{version:1,iv:b64(iv),ciphertext:b64(new Uint8Array(ciphertext))}})!==true)throw Error('erasure_evidence_not_saved');
 };
 const id=f=>JSON.stringify([f.bucket,f.path]);
 return {
  prepare:async(j,plan)=>{
   if(plan.userId!==j.userId||plan.digest!==j.reviewedPlanDigest||plan.writesRestricted!==true||!Array.isArray(plan.files))throw Error('invalid_file_plan');
   const expected=new Map(plan.files.map(f=>[id(f),f]));
   const old=await load(j);
   if(old){if(old.files.length!==expected.size||new Set(old.files.map(id)).size!==expected.size||old.files.some(f=>!expected.has(id(f))))throw Error('invalid_erasure_evidence');return true;}
   const files=[];
   for(const f of expected.values()){
    if(await rpc('advance_account_deletion_job',{p_id:j.id,p_lease:j.leaseToken,p_action:'renew',p_step:null})!==true)throw Error('lease_lost');
    if(f.subjectUserId!==j.userId||f.disposition!=='erase'||f.ownershipVerified!==true)throw Error('invalid_file_target');
    const signed=await storage.from(f.bucket).createSignedUrl(f.path,86400);
    if(signed.error||typeof signed.data?.signedUrl!=='string')throw Error('erasure_url_unavailable');
    const url=new URL(signed.data.signedUrl);
    const path='/storage/v1/object/sign/'+encodeURIComponent(f.bucket)+'/'+f.path.split('/').map(encodeURIComponent).join('/');
    if(url.origin!==base.origin||url.pathname!==path||url.username||url.password||url.hash||!url.searchParams.get('token')||[...url.searchParams.keys()].some(k=>k!=='token'&&k!=='download'))throw Error('invalid_erasure_url');
    const response=await fetchImpl(url.href,{redirect:'error',signal:AbortSignal.timeout(10000)});
    if(response.status!==200)throw Error('erasure_url_unconfirmed');
    // Drain without buffering potentially large private files into memory.
    if(!response.body)throw Error('erasure_url_unconfirmed');
    const reader=response.body.getReader();try{while(!(await reader.read()).done){}}finally{reader.releaseLock();}
    files.push({bucket:f.bucket,path:f.path,originalSignedUrl:url.href,verifiedBeforeErasureAt:new Date(now()).toISOString(),removalConfirmedAt:null});
   }
   await save(j,{jobId:j.id,userId:j.userId,planDigest:j.reviewedPlanDigest,inventoryComplete:true,files});return true;
  },
  recordRemoval:async(j,bucket,paths)=>{
   const data=await load(j);if(!data)throw Error('erasure_evidence_missing');
   // A retried remove is a NEW removal observation. Never reuse an earlier
   // timestamp to skip the propagation window after this API call.
   for(const path of paths){const f=data.files.find(f=>f.bucket===bucket&&f.path===path);if(!f)throw Error('erasure_evidence_missing');f.removalConfirmedAt=new Date(now()).toISOString();}
   await save(j,data);return true;
  },
  readEvidence:async({userId,jobId,planDigest,leaseToken})=>load({id:jobId,userId,reviewedPlanDigest:planDigest,leaseToken}),
 };
}
