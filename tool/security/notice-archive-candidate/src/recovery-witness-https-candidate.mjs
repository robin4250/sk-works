// Review-only Node TLS listener. This is not deployed or independent custody.
// Caller-owned TLS keys are never read from disk or logged here. The returned
// server is not listening until the caller explicitly binds it.
import {createServer} from 'node:https';
import {createWitnessHttpCandidate} from './recovery-witness-http-candidate.mjs';

export function createWitnessHttpsCandidate({tls, maxConcurrent=8, ...config}) {
  if(!tls || !tls.key || !tls.cert || !Number.isSafeInteger(maxConcurrent) ||
      maxConcurrent<1 || maxConcurrent>64) throw Error('invalid witness TLS configuration');
  const target=new URL(config.endpoint),handler=createWitnessHttpCandidate(config);
  const timeout=config.timeoutMs ?? 5000;
  let active=0,server;
  const small=(res,status,error)=>{
    if(res.destroyed || res.headersSent)return;
    res.writeHead(status,{'content-type':'application/json','cache-control':'no-store',
      'x-content-type-options':'nosniff','connection':'close'});
    res.end(JSON.stringify({error}));
  };
  try {
    server=createServer({key:tls.key,cert:tls.cert,minVersion:'TLSv1.3',
      maxHeaderSize:8192,headersTimeout:timeout,requestTimeout:timeout},async(req,res)=>{
      // Do not trust forwarded scheme/host headers or accept an absolute URI.
      const counts=new Map();
      for(let i=0;i<req.rawHeaders.length;i+=2){const k=req.rawHeaders[i].toLowerCase();counts.set(k,(counts.get(k)??0)+1);}
      if(req.method!=='POST'||req.url!==target.pathname||req.headers.host!==target.host||
          ['host','authorization','content-type','content-length','transfer-encoding'].some(k=>(counts.get(k)??0)>1)) {
        small(res,404,'unavailable');return;
      }
      if(active>=maxConcurrent){small(res,503,'unavailable');return;}
      active++;
      let timer,cleanup=()=>{};
      // Keep a harmless listener while a late socket error follows a rejection.
      req.on('error',()=>{});
      const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('deadline')),timeout);});
      const bounded=p=>Promise.race([p,deadline]);
      try {
        const declared=req.headers['content-length'];
        if(declared!==undefined&&(!/^\d+$/.test(declared)||Number(declared)>2048)) {
          small(res,413,'invalid request');return;
        }
        const body=await bounded(new Promise((resolve,reject)=>{
          const bytes=Buffer.alloc(2048);let length=0;
          const data=chunk=>{
            if(chunk.length>bytes.length-length){cleanup();reject(Error('body too large'));return;}
            chunk.copy(bytes,length);length+=chunk.length;
          };
          const end=()=>{cleanup();resolve(bytes.subarray(0,length));};
          const error=()=>{cleanup();reject(Error('request unavailable'));};
          cleanup=()=>{req.off('data',data);req.off('end',end);req.off('error',error);req.off('aborted',error);req.pause();};
          req.on('data',data);req.once('end',end);req.once('error',error);req.once('aborted',error);
        }));
        const response=await bounded(handler(new Request(target.href,{method:'POST',
          headers:req.headers,body})));
        const output=Buffer.from(await bounded(response.arrayBuffer()));
        if(output.length>8192)throw Error('response unavailable');
        if(!res.destroyed){res.writeHead(response.status,{'content-type':'application/json',
          'cache-control':'no-store','x-content-type-options':'nosniff','connection':'close',
          'content-length':output.length});res.end(output);}
      } catch {small(res,503,'witness outcome unknown; reconcile before retry');}
      finally {clearTimeout(timer);cleanup();active--;}
    });
  } catch {throw Error('invalid witness TLS configuration');}
  server.maxHeadersCount=16;
  server.maxConnections=maxConcurrent*2;
  server.keepAliveTimeout=1;
  server.setTimeout(timeout,socket=>socket.destroy());
  server.on('clientError',(_error,socket)=>socket.destroy());
  server.on('tlsClientError',()=>{});
  return server;
}
