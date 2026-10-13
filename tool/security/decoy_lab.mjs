/** Offline synthetic deception lab. No listener, DNS, database, or outbound I/O. */
export class DecoyLab {
  #generation=1; #events=[]; #blocked=false; #sequence=0;
  constructor({clock=()=>Date.now(),capacity=128,retentionMs=3600000}={}) {
    if(!Number.isInteger(capacity)||capacity<1||capacity>1024||!Number.isFinite(retentionMs)||retentionMs<1||retentionMs>86400000) throw Error('Invalid bounds');
    this.clock=clock; this.capacity=capacity; this.retentionMs=retentionMs;
  }
  get lure(){return `/synthetic-decoy/g${this.#generation}/fixture-records`;}
  #record(kind,generation=null){
    const at=this.clock();
    this.#events=this.#events.filter(e=>at-e.at<this.retentionMs);
    this.#events.push({sequence:++this.#sequence,at,kind,generation});
    this.#events=this.#events.slice(-this.capacity);
  }
  rotate(){if(this.#generation>=1000000)throw Error('Rotation bound');this.#generation++;this.#record('rotated',this.#generation);return this.lure;}
  setQuarantine(enabled){if(typeof enabled!=='boolean')throw Error('Invalid switch');this.#blocked=enabled;this.#record(enabled?'decoy_quarantined':'decoy_released');}
  async handle(request){
    // Do not inspect, parse, echo, or retain headers, query, body, or client identities.
    if(request.body) void request.body.cancel().catch(()=>{});
    if(request.url.length>2048){this.#record('oversized_target');return new Response(null,{status:414});}
    let path;try{path=new URL(request.url).pathname;}catch{this.#record('invalid_target');return new Response(null,{status:400});}
    const match=/^\/synthetic-decoy\/g([1-9][0-9]{0,5})\/fixture-records$/.exec(path);
    if(!match)return new Response(null,{status:404});
    const generation=Number(match[1]);
    if(generation>this.#generation)return new Response(null,{status:404});
    this.#record(generation===this.#generation?'current_lure_touched':'retired_lure_touched',generation);
    // A hit is evidence to review, never proof of malicious identity or production blocking.
    if(this.#blocked)return new Response(null,{status:503});
    if(request.method!=='GET')return new Response(null,{status:405});
    return Response.json({environment:'synthetic-only',records:[]},{headers:{'Cache-Control':'no-store'}});
  }
  inspect(){const at=this.clock();this.#events=this.#events.filter(e=>at-e.at<this.retentionMs);return structuredClone(this.#events);}
  checkpoint(){return {version:1,generation:this.#generation,quarantined:this.#blocked};}
  restore(state){
    // Restore only controller state. Request-derived data and historical logs never enter backups.
    if(!state||Object.keys(state).sort().join(',')!=='generation,quarantined,version'||state.version!==1||!Number.isInteger(state.generation)||state.generation<1||state.generation>1000000||typeof state.quarantined!=='boolean')throw Error('Invalid checkpoint');
    this.#generation=state.generation;this.#blocked=state.quarantined;this.#events=[];this.#sequence=0;this.#record('restored',this.#generation);
  }
}
