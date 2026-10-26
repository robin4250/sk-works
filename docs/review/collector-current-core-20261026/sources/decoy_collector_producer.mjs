import {createHmac} from 'node:crypto';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const hits=new Set(['current_lure_touched','retired_lure_touched']);
const keys='at,generation,kind,sequence';

/** Server-only metadata bridge. No network, persistence, credential lookup or activation. */
export class DecoyCollectorProducer {
  #key;#collector;#session;#clock;#lastNow=-1;#closed=false;
  constructor({collectorId,sessionId,derivationKey,clock=()=>Date.now()}) {
    if(!uuid.test(collectorId)||!uuid.test(sessionId)||!Buffer.isBuffer(derivationKey)||derivationKey.length!==32||typeof clock!=='function')throw Error('Invalid producer configuration');
    this.#key=Buffer.from(derivationKey);this.#collector=collectorId;this.#session=sessionId;this.#clock=clock;
  }
  #digest(domain,value){return createHmac('sha256',this.#key).update(`sko-decoy-producer-v1\n${domain}\n${this.#collector}\n${this.#session}\n${value}`).digest('hex');}
  build(input){
    if(this.#closed)throw Error('Producer closed');
    const now=this.#clock();
    if(!Number.isSafeInteger(now)||now<1000000000000||now>9999999999999||now<this.#lastNow)throw Error('Producer clock unavailable');
    this.#lastNow=now;
    if(!input||Array.isArray(input)||typeof input!=='object'||Object.keys(input).sort().join(',')!==keys||!Number.isSafeInteger(input.sequence)||input.sequence<1||!Number.isSafeInteger(input.at)||input.at<now-600000||input.at>now+30000||typeof input.kind!=='string')throw Error('Invalid decoy event');
    // Only the existing controller's two contact kinds enter the current collector protocol.
    // Control/limit events require their own reviewed event schema; do not relabel them as hits.
    if(!hits.has(input.kind))return null;
    if(!Number.isInteger(input.generation)||input.generation<1||input.generation>1000000)throw Error('Invalid decoy event');
    const raw=this.#digest('event-id',String(input.sequence));
    const eventId=`${raw.slice(0,8)}-${raw.slice(8,12)}-4${raw.slice(13,16)}-${((parseInt(raw[16],16)&3)|8).toString(16)}${raw.slice(17,20)}-${raw.slice(20,32)}`;
    const at=new Date(input.at).toISOString();
    const event=Object.freeze({event_id:eventId,collector_id:this.#collector,occurred_at:at,event_kind:input.kind,generation:input.generation,
      correlation_key:this.#digest('decoy-generation',String(input.generation)),key_epoch:at.slice(0,10)});
    // Immutable UTF-8 text, rather than a mutable Buffer: retry these exact bytes and event_id.
    return Object.freeze({event,body:JSON.stringify(event),source_tracking:'decoy_generation_only'});
  }
  close(){this.#key.fill(0);this.#closed=true;}
}
