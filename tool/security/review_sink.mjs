/** Synthetic local review queue. Not a notification transport or account-blocking system. */
const kinds=new Set(['current_lure_touched','retired_lure_touched']);
export class ReviewSink {
  #items=[]; #lastSequence=0;
  constructor({clock=()=>Date.now(),capacity=32,retentionMs=3600000}={}){
    if(typeof clock!=='function'||!Number.isInteger(capacity)||capacity<1||capacity>128||!Number.isFinite(retentionMs)||retentionMs<1||retentionMs>86400000)throw Error('Invalid bounds');
    Object.defineProperties(this,{clock:{value:clock},capacity:{value:capacity},retentionMs:{value:retentionMs}});
  }
  ingest(event){
    if(!event||Object.keys(event).sort().join(',')!=='at,generation,kind,sequence'||!kinds.has(event.kind)||!Number.isInteger(event.sequence)||event.sequence<=this.#lastSequence||!Number.isInteger(event.generation)||event.generation<1||event.generation>1000000||!Number.isFinite(event.at))return false;
    const now=this.clock();
    if(event.at>now||now-event.at>=this.retentionMs)return false;
    this.#lastSequence=event.sequence;
    this.#items=this.#items.filter(x=>now-x.at<this.retentionMs);
    this.#items.push({...event,state:'needs_review'});
    this.#items=this.#items.slice(-this.capacity);
    return true;
  }
  dismiss(sequence){const item=this.#items.find(x=>x.sequence===sequence);if(!item)return false;item.state='dismissed';return true;}
  inspect(){const now=this.clock();this.#items=this.#items.filter(x=>now-x.at<this.retentionMs);return structuredClone(this.#items);}
}
