import {DecoyLab} from './decoy_lab.mjs';
const encoder=new TextEncoder();
const label=/^[a-zA-Z0-9_-]{1,48}$/;
const fields=(x,names)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).sort().join(',')===names;
const bytes=x=>encoder.encode(JSON.stringify(x));
const validState=s=>fields(s,'generation,quarantined,version')&&s.version===1&&Number.isInteger(s.generation)&&s.generation>=1&&s.generation<=1000000&&typeof s.quarantined==='boolean';
/** Trusted process-local monotonic ledger; never reconstructed from attacker checkpoints. */
export class MemoryCheckpointLedger {
  #issued=0;#accepted=0;
  issue(){if(this.#issued>=Number.MAX_SAFE_INTEGER)throw Error('Revision bound');return ++this.#issued;}
  accept(revision){if(!Number.isSafeInteger(revision)||revision<=this.#accepted||revision>this.#issued)return false;this.#accepted=revision;return true;}
}
/** Operator-only in-memory wrapper. No endpoints, credentials, persistence or deployment. */
export class SignedDecoyController {
  #lab;#key;#keyId;#scope;#ledger;
  constructor({key,keyId,scope,ledger,lab=new DecoyLab()}){
    if(!(key instanceof CryptoKey)||key.extractable||key.algorithm.name!=='HMAC'||key.algorithm.hash.name!=='SHA-256'||key.algorithm.length<256||!key.usages.includes('sign')||!key.usages.includes('verify')||!label.test(keyId)||!label.test(scope)||!(ledger instanceof MemoryCheckpointLedger)||!(lab instanceof DecoyLab))throw Error('Invalid trust boundary');
    this.#key=key;this.#keyId=keyId;this.#scope=scope;this.#ledger=ledger;this.#lab=lab;
  }
  get lure(){return this.#lab.lure;}
  handle(request){return this.#lab.handle(request);}
  rotate(){return this.#lab.rotate();}
  setQuarantine(value){return this.#lab.setQuarantine(value);}
  inspect(){return this.#lab.inspect();}
  async checkpoint(){
    const payload={version:1,scope:this.#scope,keyId:this.#keyId,revision:this.#ledger.issue(),state:this.#lab.checkpoint()};
    const signature=Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',this.#key,bytes(payload))));
    return {payload,signature};
  }
  async restore(envelope){
    // All values are validated and copied before the first await: caller cannot race mutation.
    if(!fields(envelope,'payload,signature'))throw Error('Checkpoint rejected');
    const p=envelope.payload,s=envelope.signature;
    if(!fields(p,'keyId,revision,scope,state,version')||p.version!==1||p.scope!==this.#scope||p.keyId!==this.#keyId||!Number.isSafeInteger(p.revision)||p.revision<1||!validState(p.state)||!Array.isArray(s)||s.length!==32||!s.every(v=>Number.isInteger(v)&&v>=0&&v<=255))throw Error('Checkpoint rejected');
    const payload={version:1,scope:p.scope,keyId:p.keyId,revision:p.revision,state:{version:1,generation:p.state.generation,quarantined:p.state.quarantined}};
    if(!await crypto.subtle.verify('HMAC',this.#key,new Uint8Array(s),bytes(payload)))throw Error('Checkpoint rejected');
    // No await between atomic ledger consumption and controller restore.
    if(!this.#ledger.accept(payload.revision))throw Error('Checkpoint rejected');
    this.#lab.restore(payload.state);
  }
}
