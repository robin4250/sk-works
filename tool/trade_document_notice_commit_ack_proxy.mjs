// CI fixture only. Parses PostgreSQL backend protocol v3 frames, then drops the
// real COMMIT CommandComplete before a client can receive its acknowledgement.
// No TLS/hosted endpoint, credential logging, retry or product import is allowed.
import net from 'node:net';

const LIMIT=8*1024*1024;
export async function createNoticeCommitAckProxy(target,{reviewOnly=false}={}){
 let u;try{u=new URL(target);}catch{throw Error('isolated notice acknowledgement fixture required');}
 if(!reviewOnly||process.env.CI!=='true'||u.protocol!=='postgresql:'||
  !['127.0.0.1','localhost','[::1]'].includes(u.hostname)||u.pathname!=='/sko_document_consent_fixture'||
  u.username!=='postgres'||u.password!=='fixture-only'||!u.port||u.search||u.hash||
  Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
  throw Error('isolated notice acknowledgement fixture required');
 const pairs=new Set();let accepted=false,armed=false,dropped=false,closed=false,notifyDrop;
 const drop=new Promise(resolve=>{notifyDrop=resolve;});
 const server=net.createServer(front=>{
  if(accepted||closed){front.destroy();return;}accepted=true;
  const back=net.connect({host:u.hostname.replace(/^\[|\]$/g,''),port:Number(u.port)});
  const pair={front,back};pairs.add(pair);
  let buffered=Buffer.alloc(0),sent=0,received=0;
  const destroy=()=>{buffered=Buffer.alloc(0);front.destroy();back.destroy();};
  const hardTimer=setTimeout(destroy,15000);
  front.setTimeout(15000,destroy);back.setTimeout(15000,destroy);
  front.on('error',destroy);back.on('error',destroy);
  front.on('close',()=>{clearTimeout(hardTimer);buffered=Buffer.alloc(0);pairs.delete(pair);back.destroy();});
  back.on('end',()=>front.end());
  back.on('close',()=>{if(!back.readableEnded)front.destroy();});
  front.on('data',chunk=>{
   sent+=chunk.length;if(sent>LIMIT){destroy();return;}
   if(!back.write(chunk))front.pause();
  });
  back.on('drain',()=>front.resume());
  back.on('data',chunk=>{
   received+=chunk.length;
   if(received>LIMIT||buffered.length+chunk.length>LIMIT){destroy();return;}
   buffered=Buffer.concat([buffered,chunk]);
   while(buffered.length>=5){
    const length=buffered.readUInt32BE(1);
    if(length<4||length>LIMIT-1){destroy();return;}
    if(buffered.length<length+1)return;
    const frame=buffered.subarray(0,length+1);buffered=buffered.subarray(length+1);
    if(armed&&frame[0]===67&&frame.subarray(5).equals(Buffer.from('COMMIT\0'))){
     dropped=true;notifyDrop();destroy();return;
    }
    if(!front.write(frame))back.pause();
   }
  });
  front.on('drain',()=>back.resume());
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',()=>{server.off('error',reject);resolve();});});
 server.on('error',()=>{for(const p of pairs){p.front.destroy();p.back.destroy();}});
 const address=server.address();
 if(typeof address!=='object'||address===null){server.close();throw Error('fixture listener unavailable');}
 const proxy=new URL(u);proxy.hostname='127.0.0.1';proxy.port=String(address.port);proxy.searchParams.set('sslmode','disable');
 return {
  connectionString:proxy.href,
  armCommitDrop(){if(closed||armed||dropped||pairs.size!==1)throw Error('fixture connection is not ready');armed=true;},
  async waitForDrop(){
   let timer;
   try{await Promise.race([drop,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('COMMIT acknowledgement was not dropped')),5000);})]);}
   finally{clearTimeout(timer);}
  },
  get dropped(){return dropped;},
  async close(){
   if(closed)return;closed=true;
   for(const p of pairs){p.front.destroy();p.back.destroy();}
   await new Promise(resolve=>server.close(resolve));
  },
 };
}
