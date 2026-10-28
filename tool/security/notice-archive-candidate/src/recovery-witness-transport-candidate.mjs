// Review-only transport. No deployed witness, credentials or recovery activation.
// The caller must provision the endpoint, bearer and pinned witness key through
// independently controlled configuration. A valid signature alone is not custody.
import {randomBytes} from 'node:crypto';
import {validateWitnessReceipt} from './recovery-witness-model.mjs';

export async function requestWitnessReceipt({endpoint,bearer,key,operation,scope,nonce,proposalHash,minSequence,
  now=Date.now,fetchImpl=fetch,timeoutMs=5000}) {
  const fail=()=>new Error('witness outcome unknown; reconcile before retry');
  let url;
  try { url=new URL(endpoint); } catch { throw fail(); }
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||
      !['consume','lookup'].includes(operation)||typeof bearer!=='string'||bearer.length<16||bearer.length>4096||
      /[\r\n]/.test(bearer)||typeof scope!=='string'||scope.length<1||scope.length>200||
      !/^[a-f0-9]{64}$/.test(nonce)||!/^[a-f0-9]{64}$/.test(proposalHash)||
      !Number.isSafeInteger(minSequence)||minSequence<1||!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>30000) throw fail();
  const challenge=randomBytes(32).toString('hex');
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeoutMs);
  let reader;
  try {
    // Exactly one attempt. An HTTP/network error may follow a remote commit.
    const response=await fetchImpl(url.href,{method:'POST',redirect:'error',cache:'no-store',
      signal:controller.signal,headers:{authorization:`Bearer ${bearer}`,'content-type':'application/json',accept:'application/json'},
      body:JSON.stringify({operation,scope,nonce,proposalHash,challenge})});
    if(!response.ok||response.redirected||response.url&&response.url!==url.href||
        response.headers.get('content-type')?.split(';')[0].trim()!=='application/json'||!response.body) throw fail();
    const declared=response.headers.get('content-length');
    if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>8192)) throw fail();
    reader=response.body.getReader();
    const bytes=new Uint8Array(8192);let length=0;
    while(true){const {done,value}=await reader.read();if(done)break;
      if(!(value instanceof Uint8Array)||value.length>bytes.length-length)throw fail();
      bytes.set(value,length);length+=value.length;
    }
    const receipt=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(0,length)));
    return validateWitnessReceipt(receipt,{scope,nonce,proposalHash,challenge,key,now:now(),minSequence});
  } catch { throw fail(); }
  finally { clearTimeout(timer);controller.abort();if(reader){try{await reader.cancel();}catch{}reader.releaseLock();} }
}
