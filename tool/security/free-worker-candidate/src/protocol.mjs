const te=new TextEncoder(),hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
export const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function hmacHex(key,bytes){return hex(await crypto.subtle.sign('HMAC',key,bytes));}
export async function importHmac(bytes){if(!(bytes instanceof Uint8Array)||bytes.byteLength!==32)throw Error('Dedicated 32-byte key required');return crypto.subtle.importKey('raw',bytes,{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);}
export async function signCollectorV1({key,collectorId,timestamp,body}){
 if(!uuid.test(collectorId)||!Number.isSafeInteger(timestamp)||timestamp<0||typeof body!=='string'||te.encode(body).length>1024)throw Error('Signing input rejected');
 return hmacHex(key,te.encode(`sko-collector-v1\n${collectorId}\n${timestamp}\n${body}`));
}
export async function signCollectorV2({key,collectorId,keyVersion,timestamp,body}){
 const length=typeof body==='string'?te.encode(body).length:0;
 if(!uuid.test(collectorId)||!Number.isInteger(keyVersion)||keyVersion<1||keyVersion>1000000||!Number.isSafeInteger(timestamp)||timestamp<0||length<1||length>1024)throw Error('Signing input rejected');
 return hmacHex(key,te.encode(`sko-collector-v2\n${collectorId}\n${keyVersion}\n${timestamp}\n${body}`));
}
export async function producerEvent({key,collectorId,sessionId,sequence,at,kind,generation}){
 if(!uuid.test(collectorId)||!uuid.test(sessionId)||!Number.isSafeInteger(sequence)||sequence<1||!Number.isSafeInteger(at)||!['current_lure_touched','retired_lure_touched'].includes(kind)||!Number.isInteger(generation)||generation<1||generation>1000000)throw Error('Event input rejected');
 const derive=(domain,value)=>hmacHex(key,te.encode(`sko-decoy-producer-v1\n${domain}\n${collectorId}\n${sessionId}\n${value}`));
 const raw=await derive('event-id',String(sequence)),event_id=`${raw.slice(0,8)}-${raw.slice(8,12)}-4${raw.slice(13,16)}-${((parseInt(raw[16],16)&3)|8).toString(16)}${raw.slice(17,20)}-${raw.slice(20,32)}`;
 const occurred_at=new Date(at).toISOString();
 return {event_id,collector_id:collectorId,occurred_at,event_kind:kind,generation,correlation_key:await derive('decoy-generation',String(generation)),key_epoch:occurred_at.slice(0,10)};
}
export async function issueCapability(key,{epoch,expires,nonce}){
 const payload=JSON.stringify({v:1,audience:'sko-synthetic-decoy',method:'GET',epoch,expires,nonce});
 return btoa(payload).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')+'.'+await hmacHex(key,te.encode('sko-decoy-capability-v1\n'+payload));
}
export async function verifyCapability(key,token,now){
 if(typeof token!=='string'||token.length>512||!/^[-_A-Za-z0-9]+\.[a-f0-9]{64}$/.test(token))return null;
 try{const [raw,mac]=token.split('.'),payload=atob(raw.replaceAll('-','+').replaceAll('_','/')),p=JSON.parse(payload);
 if(Object.keys(p).sort().join(',')!=='audience,epoch,expires,method,nonce,v'||p.v!==1||p.audience!=='sko-synthetic-decoy'||p.method!=='GET'||!Number.isSafeInteger(p.epoch)||p.epoch<1||!Number.isSafeInteger(p.expires)||p.expires<=now||p.expires>now+60000||!uuid.test(p.nonce))return null;
 const bytes=Uint8Array.from(mac.match(/../g),x=>parseInt(x,16));
 return await crypto.subtle.verify('HMAC',key,bytes,te.encode('sko-decoy-capability-v1\n'+payload))?p:null;
 }catch{return null;}
}
