import { createHash } from 'node:crypto';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const failure = () => Error('storage_snapshot_unavailable');

// Isolated REST candidate, not wired into the inspector. The host declaration is
// not deployment evidence by itself. An operator must first verify the deployed
// Storage implementation, versionId behavior and metadata adapter in staging.
export function createQualificationVersionedStorageReader({projectRef,verifiedDeployment,accessTokenProvider,readMetadata,fetchImpl=fetch,timeoutMs=5000}) {
  if (typeof projectRef !== 'string' || !/^[a-z0-9]{20}$/.test(projectRef) || verifiedDeployment?.projectRef !== projectRef || verifiedDeployment?.restVersionId !== true || (typeof verifiedDeployment?.sourceCommit !== 'string' || !/^[a-f0-9]{40}$/.test(verifiedDeployment.sourceCommit)) || typeof accessTokenProvider !== 'function' || typeof readMetadata !== 'function' || typeof fetchImpl !== 'function' || !Number.isSafeInteger(timeoutMs) || timeoutMs < 10 || timeoutMs > 10000) throw failure();
  return async function readSelectedVersion({bucket,path,objectId,version,maxBytes,expectedBytes,expectedSha256}) {
    if (bucket !== 'qualification-certificates' || typeof path !== 'string' || path.length > 1024 || !path || path.includes('..') || path.includes('\\') || path.split('/').some(x => !x) || (typeof objectId !== 'string' || !uuid.test(objectId)) || typeof version !== 'string' || !uuid.test(version) || !Number.isSafeInteger(maxBytes) || maxBytes < 8 || maxBytes > 20971520 || !Number.isSafeInteger(expectedBytes) || expectedBytes < 8 || expectedBytes > maxBytes || (typeof expectedSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(expectedSha256))) throw failure();
    const controller = new AbortController();
    let timer, reader;
    const matches = value => value?.id === objectId && value?.version === version && value?.bucket === bucket && value?.path === path && value?.archived === false && value?.deleted === false;
    const scope = Object.freeze({bucket,path,objectId,version});
    const work = async () => {
      if (!matches(await readMetadata(scope,controller.signal)) || controller.signal.aborted) throw failure();
      const token = await accessTokenProvider(scope,controller.signal);
      if (controller.signal.aborted || typeof token !== 'string' || !token || token.length > 8192 || /[\r\n]/.test(token)) throw failure();
      const url = new URL(`https://${projectRef}.supabase.co/storage/v1/object/authenticated/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`);
      url.searchParams.set('versionId',version);
      const result = await fetchImpl(url,{method:'GET',redirect:'error',cache:'no-store',headers:{authorization:`Bearer ${token}`,'accept-encoding':'identity'},signal:controller.signal});
      if (controller.signal.aborted || result.status !== 200 || result.redirected || !result.body) throw failure();
      const length = result.headers.get('content-length');
      if (length !== null && (!/^[1-9][0-9]*$/.test(length) || Number(length) !== expectedBytes)) throw failure();
      const encoding = result.headers.get('content-encoding');
      if (encoding !== null && encoding !== 'identity') throw failure();
      reader = result.body.getReader();
      const chunks=[]; let size=0, count=0;
      for (;;) {
        const part=await reader.read();
        if (controller.signal.aborted) throw failure();
        if (part.done) break;
        if (!(part.value instanceof Uint8Array) || ++count > 4096 || part.value.length === 0 || (size += part.value.length) > expectedBytes) throw failure();
        chunks.push(Uint8Array.from(part.value));
      }
      if (size !== expectedBytes) throw failure();
      const bytes=new Uint8Array(size); let offset=0;
      for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.length; }
      if (createHash('sha256').update(bytes).digest('hex') !== expectedSha256 || !matches(await readMetadata(scope,controller.signal)) || controller.signal.aborted) throw failure();
      return {objectId,version,bytes};
    };
    try {
      return await Promise.race([work(),new Promise((_,reject) => {timer=setTimeout(() => {controller.abort();reject(failure());},timeoutMs);})]);
    } catch (_) { throw failure(); }
    finally { clearTimeout(timer); controller.abort(); if (reader) {reader.cancel().catch(()=>{});try{reader.releaseLock();}catch{}} }
  };
}
