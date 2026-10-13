// Server-only adapter. Evidence must come from private, job-bound storage and
// contain URLs actually fetched before erasure, never a client request body.
// No URL/token/provider body is returned or included in errors.
export function createErasedFileProbe({storage,readEvidence,origin,fetchImpl=fetch,now=Date.now}) {
 const base=new URL(origin);
 if(base.protocol!=='https:' || base.username || base.password || base.pathname!=='/' || base.search || base.hash)
  throw Error('invalid_storage_origin');
 if(typeof storage?.from!=='function'||typeof readEvidence!=='function')throw Error('erasure_probe_ports_missing');
 const key=f=>JSON.stringify([f.bucket,f.path]);
 const pathOK=p=>typeof p==='string' && p.length>0 && p.length<=1024 && !/[\\\x00-\x1f]/.test(p)
  && p.split('/').every(s=>s && s!=='.' && s!=='..');
 return async ({userId,jobId,planDigest,files,leaseToken})=>{
  try {
   if(!/^[a-f0-9]{64}$/.test(planDigest)||!Array.isArray(files))return null;
   const expected=new Map();
   for(const f of files){
    if(f?.subjectUserId!==userId || f.disposition!=='erase' || f.ownershipVerified!==true ||
      typeof f.bucket!=='string' || !/^[a-z0-9-]+$/.test(f.bucket) || !pathOK(f.path))return null;
    expected.set(key(f),f);
   }
   const evidence=await readEvidence({userId,jobId,planDigest,leaseToken});
   if(evidence?.userId!==userId || evidence.jobId!==jobId || evidence.planDigest!==planDigest ||
     evidence.inventoryComplete!==true || !Array.isArray(evidence.files) || evidence.files.length!==expected.size)return null;
   const checked=new Set(); const targets=[];
   // Validate every target before making ANY outbound request (SSRF protection).
   for(const f of evidence.files){
    const k=key(f);if(!expected.has(k)||checked.has(k))return null;
    const url=new URL(f.originalSignedUrl);
    const path='/storage/v1/object/sign/'+encodeURIComponent(f.bucket)+'/'+f.path.split('/').map(encodeURIComponent).join('/');
    if(url.origin!==base.origin || url.username || url.password || url.hash || url.pathname!==path ||
      !url.searchParams.get('token') || [...url.searchParams.keys()].some(k=>k!=='token'&&k!=='download'))return null;
    const observed=Date.parse(f.verifiedBeforeErasureAt),removed=Date.parse(f.removalConfirmedAt);
    // Documented CDN propagation is at most 60s; time alone never passes:
    // exact original URL and authenticated object absence are both checked below.
    if(!Number.isFinite(observed)||!Number.isFinite(removed)||observed>removed||removed>now()-60000)return null;
    checked.add(k);targets.push({...f,url:url.href});
   }
   for(const f of targets){
    const exists=await storage.from(f.bucket).exists(f.path);
    if(exists.error || exists.data!==false)return null;
    const response=await fetchImpl(f.url,{redirect:'error',signal:AbortSignal.timeout(10000)});
    if(![400,404].includes(response.status))return null;
    const body=await response.json();
    // Auth expiry, forbidden, timeout, proxy and generic 404 do not prove erasure.
    if(String(body?.statusCode)!=='404' || body.message!=='Object not found')return null;
   }
   return {userId,jobId,planDigest,allObjectsAbsent:true,existingSignedUrlsInvalidated:true};
  }catch{return null;}
 };
}
