import http from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { DecoyLab } from './decoy_lab.mjs';

/** Disposable loopback fixture only. No CLI, public binding, production adapter or outbound I/O. */
export async function startIsolatedTransport({operatorToken, clock=()=>Date.now(), maxBodyBytes=1024,
  maxUrlBytes=256, deadlineMs=250, maxConcurrent=2, rateLimit=30, windowMs=1000,
  eventCapacity=32, retentionMs=60000}={}) {
  if(typeof operatorToken!=='string'||!/^[a-f0-9]{64}$/.test(operatorToken)||typeof clock!=='function')throw Error('Invalid fixture configuration');
  for(const [value,min,max] of [[maxBodyBytes,1,4096],[maxUrlBytes,64,2048],[deadlineMs,20,2000],
    [maxConcurrent,1,8],[rateLimit,1,100],[windowMs,100,60000],[eventCapacity,1,128],[retentionMs,1,3600000]]) {
    if(!Number.isInteger(value)||value<min||value>max)throw Error('Invalid fixture bounds');
  }
  const tokenHash=createHash('sha256').update(operatorToken).digest();
  const lab=new DecoyLab({clock});const events=[];const metrics={accepted:0,rejected:0,dropped:0,expired:0};
  let active=0,windowStart=clock(),windowCount=0,lastNow=windowStart;
  const now=()=>{const t=clock();if(!Number.isSafeInteger(t)||t<lastNow)throw Error('Clock unavailable');lastNow=t;return t;};
  const prune=t=>{while(events.length&&t-events[0].at>=retentionMs){events.shift();metrics.expired++;}};
  const record=(kind,t)=>{prune(t);if(events.length===eventCapacity){events.shift();metrics.dropped++;}events.push({kind,at:t});};
  const server=http.createServer({maxHeaderSize:4096,headersTimeout:deadlineMs,requestTimeout:deadlineMs},(req,res)=>{
    let ended=false,counted=false;const finish=(status,body='')=>{if(ended)return;ended=true;clearTimeout(timer);
      res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','Connection':'close'});res.end(body);
      res.once('finish',()=>req.destroy());};
    const timer=setTimeout(()=>{metrics.rejected++;finish(408);},deadlineMs);
    res.once('close',()=>{clearTimeout(timer);if(counted)active--;});
    req.on('error',()=>finish(400));
    let t;try{t=now();}catch{metrics.rejected++;finish(503);return;}
    if(Buffer.byteLength(req.url??'')>maxUrlBytes){metrics.rejected++;record('url_limit',t);finish(414);return;}
    if(t-windowStart>=windowMs){windowStart=t;windowCount=0;}
    if(++windowCount>rateLimit){metrics.rejected++;record('rate_limit',t);finish(429);return;}
    if(active>=maxConcurrent){metrics.rejected++;record('concurrency_limit',t);finish(503);return;}
    active++;counted=true;
    const length=req.headers['content-length'];
    if(length!==undefined&&(!/^\d+$/.test(length)||Number(length)>maxBodyBytes)){
      metrics.rejected++;record('body_limit',t);finish(413);return;
    }
    let size=0;
    req.on('data',chunk=>{if(ended)return;size+=chunk.length;if(size>maxBodyBytes){metrics.rejected++;record('body_limit',t);finish(413);}});
    req.on('end',async()=>{
      if(ended)return;
      if(req.url?.startsWith('/operator/')){
        const supplied=req.headers.authorization;
        if(typeof supplied!=='string'||!supplied.startsWith('Bearer ')||
          !timingSafeEqual(createHash('sha256').update(supplied.slice(7)).digest(),tokenHash)){
          metrics.rejected++;record('control_denied',t);finish(403);return;
        }
        if(req.method!=='POST'){finish(405);return;}
        try{
          if(req.url==='/operator/rotate')lab.rotate();
          else if(req.url==='/operator/quarantine')lab.setQuarantine(true);
          else if(req.url==='/operator/release')lab.setQuarantine(false);
          else{finish(404);return;}
          metrics.accepted++;record('control_accepted',t);finish(204);
        }catch{metrics.rejected++;finish(503);}return;
      }
      try{
        const result=await lab.handle(new Request(`http://127.0.0.1${req.url}`,{method:req.method}));
        metrics.accepted++;record('fixture_request',t);finish(result.status,await result.text());
      }catch{metrics.rejected++;finish(503);}
    });
  });
  server.maxConnections=16;server.keepAliveTimeout=1;
  server.on('connection',socket=>socket.setTimeout(deadlineMs,()=>socket.destroy()));
  server.on('clientError',(_error,socket)=>{metrics.rejected++;socket.destroy();});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  return Object.freeze({origin:`http://127.0.0.1:${server.address().port}`,
    inspect(){const t=now();prune(t);return structuredClone({metrics,events,active,lure:lab.lure});},
    close:()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();})});
}
