import {createHash} from 'node:crypto';

// Review-only, server-internal standard upload boundary. The caller must freeze
// and independently authorize the own-record inventory before invoking it.
// No API grant, endpoint, overwrite, retry, catalog seal or privacy proof here.
// This prevents this writer from replacing an object; it is NOT provider object
// lock, immutable retention, or protection against privileged Storage operators.
export function createVaultCreateOnlyUpload({origin,bucket,publishableKey,
  authorizationHeader,fetchImpl=fetch,timeoutMs=15000}) {
  const base=new URL(origin);
  if(base.protocol!=='https:'||base.username||base.password||base.search||base.hash||
      base.pathname!=='/'||!/^[a-z0-9][a-z0-9_-]{0,62}$/.test(bucket)||
      !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey)||
      typeof authorizationHeader!=='function'||typeof fetchImpl!=='function'||
      !Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000)
    throw Error('vault_upload_config_invalid');
  return async ({ownerId,artifactKey,pdfSha256,bytes})=>{
    if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(ownerId??'')||
        !/^[a-f0-9]{64}$/.test(artifactKey??'')||!/^[a-f0-9]{64}$/.test(pdfSha256??'')||
        !Buffer.isBuffer(bytes)||bytes.length<12||bytes.length>6*1024*1024)
      throw Error('vault_upload_request_invalid');
    // Detach before the first await, so auth resolution cannot change what is
    // hashed/uploaded. Larger originals are unsupported, never truncated.
    const body=Buffer.from(bytes);
    if(!body.subarray(0,5).equals(Buffer.from('%PDF-'))||
        !/%%EOF\s*$/.test(body.subarray(Math.max(0,body.length-1024)).toString('latin1'))||
        createHash('sha256').update(body).digest('hex')!==pdfSha256)
      throw Error('vault_upload_bytes_rejected');
    const path=`personal-vault/${ownerId}/${artifactKey}.pdf`;
    const url=new URL(`/storage/v1/object/${bucket}/${path}`,base);
    const abort=new AbortController();let timer,response;
    const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{
      abort.abort();reject(Error('vault_upload_outcome_unknown'));
    },timeoutMs);});
    const within=f=>Promise.race([Promise.resolve().then(f),deadline]);
    try {
      const bearer=await within(authorizationHeader);
      if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9_.-]+$/.test(bearer))
        throw Error('vault_upload_session_invalid');
      // One attempt only. A lost response can follow a committed upload.
      response=await within(()=>fetchImpl(url.href,{method:'POST',redirect:'error',
        cache:'no-store',signal:abort.signal,headers:{Authorization:bearer,
          apikey:publishableKey,'Content-Type':'application/pdf','Cache-Control':'no-store',
          'x-upsert':'false'},body}));
      if(![200,201].includes(response.status)||response.redirected===true||
          (response.url&&response.url!==url.href)) throw Error('vault_upload_outcome_unknown');
      // An HTTP acknowledgement is not a retained-version or content receipt.
      // Read back through the existing bounded download/hash verifier and obtain
      // trusted metadata before recording/sealing any archive catalog item.
      return Object.freeze({status:'created_unverified',objectPath:path,
        pdfSha256,byteLength:body.length});
    } catch(error) {
      if(error instanceof Error&&error.message==='vault_upload_session_invalid')throw error;
      // Do not expose URLs, provider error bodies, credentials or exception text.
      throw Error('vault_upload_outcome_unknown');
    } finally {
      clearTimeout(timer);abort.abort();
      if(response?.body?.cancel){try{Promise.resolve(response.body.cancel()).catch(()=>{});}catch{}}
    }
  };
}
