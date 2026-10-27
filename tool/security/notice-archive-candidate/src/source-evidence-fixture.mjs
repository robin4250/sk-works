// Offline review prototype only. No DB, network, key custody or deletion.
// The caller must obtain the exact source snapshot under a trusted DB lock.
import {createCipheriv,createDecipheriv,createHash,createHmac,randomBytes,timingSafeEqual} from 'node:crypto';
const hex=x=>createHash('sha256').update(x).digest('hex');
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===keys.split(',').sort().join(',');
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(x);
const b64=x=>typeof x==='string'&&/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(x)&&Buffer.from(x,'base64').toString('base64')===x;
const exactPayload='collector_id,correlation_key,event_id,event_kind,generation,key_epoch,occurred_at';
function metadata(payload){
 if(!exact(payload,exactPayload)||!uuid(payload.collector_id)||!uuid(payload.event_id)||!['current_lure_touched','retired_lure_touched'].includes(payload.event_kind)||!Number.isSafeInteger(payload.generation)||payload.generation<1||payload.generation>1000000||!/^[0-9a-f]{64}$/.test(payload.correlation_key)||!/^\d{4}-\d{2}-\d{2}$/.test(payload.key_epoch)||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(payload.occurred_at)||Number.isNaN(Date.parse(payload.occurred_at)))throw Error('invalid metadata');
 return payload;
}
export function verifyFixtureSource(e,expected,key){
 if(!exact(e,'collector_id,key_version,timestamp,body_base64,signature')||!uuid(e.collector_id)||!Number.isSafeInteger(e.key_version)||e.key_version<1||!Number.isSafeInteger(e.timestamp)||e.timestamp<1000000000000||e.timestamp>9999999999999||!b64(e.body_base64)||!/^[0-9a-f]{64}$/.test(e.signature)||!Buffer.isBuffer(key)||key.length!==32)throw Error('invalid source');
 const raw=Buffer.from(e.body_base64,'base64');if(!raw.length||raw.length>1024)throw Error('invalid source');
 const expectedMac=createHmac('sha256',key).update(`sko-collector-v2\n${e.collector_id}\n${e.key_version}\n${e.timestamp}\n`).update(raw).digest();if(!timingSafeEqual(expectedMac,Buffer.from(e.signature,'hex')))throw Error('source MAC rejected');
 const body=metadata(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw))),reference=metadata(expected);
 if(body.collector_id!==e.collector_id||Object.keys(reference).some(k=>body[k]!==reference[k]))throw Error('source metadata mismatch');
 // This independent Node parser is not a replacement for Postgres jsonb and
 // duplicate-key ingress validation. The DB verifier remains mandatory.
 return {event_id:body.event_id,raw_sha256:hex(raw)};
}
export function encryptFixtureEvidence(e,expected,key,archiveKey,companyId){
 if(!uuid(companyId)||!Buffer.isBuffer(archiveKey)||archiveKey.length!==32)throw Error('invalid archive key');
 const {event_id,raw_sha256}=verifyFixtureSource(e,expected,key),iv=randomBytes(12),aad=Buffer.from(`sko-archive-v1\n${companyId}\n${event_id}\n${raw_sha256}`);
 const cipher=createCipheriv('aes-256-gcm',archiveKey,iv);cipher.setAAD(aad);const encrypted=Buffer.concat([cipher.update(JSON.stringify(e),'utf8'),cipher.final()]);
 return {v:1,company_id:companyId,event_id,raw_sha256,iv:iv.toString('base64'),ciphertext:encrypted.toString('base64'),tag:cipher.getAuthTag().toString('base64')};
}
export function decryptFixtureEvidence(box,companyId,archiveKey){
 if(!exact(box,'v,company_id,event_id,raw_sha256,iv,ciphertext,tag')||box.v!==1||box.company_id!==companyId||!uuid(companyId)||!uuid(box.event_id)||!/^[0-9a-f]{64}$/.test(box.raw_sha256)||![box.iv,box.ciphertext,box.tag].every(b64)||!Buffer.isBuffer(archiveKey)||archiveKey.length!==32)throw Error('invalid archive');
 const iv=Buffer.from(box.iv,'base64'),tag=Buffer.from(box.tag,'base64');if(iv.length!==12||tag.length!==16||Buffer.from(box.ciphertext,'base64').length>4096)throw Error('invalid archive');
 const dec=createDecipheriv('aes-256-gcm',archiveKey,iv);dec.setAAD(Buffer.from(`sko-archive-v1\n${companyId}\n${box.event_id}\n${box.raw_sha256}`));dec.setAuthTag(tag);
 const e=JSON.parse(Buffer.concat([dec.update(Buffer.from(box.ciphertext,'base64')),dec.final()]).toString('utf8'));if(!b64(e.body_base64)||hex(Buffer.from(e.body_base64,'base64'))!==box.raw_sha256)throw Error('archive digest mismatch');return e;
}
