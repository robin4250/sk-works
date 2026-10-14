const kinds=new Set(['current_lure_touched','retired_lure_touched']);
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const iso=n=>new Date(n).toISOString();
/** Offline trusted-adapter collector. Input trust is NOT established by a client-supplied header. */
export class IncidentCollector {
  #events=[];#incidents=[];#lastNow;#started;#droppedThrough=-Infinity;
  constructor({clock=()=>Date.now(),capacity=128,retentionMs=120000,beforeMs=30000,afterMs=30000}={}){
    if(typeof clock!=='function'||![capacity,retentionMs,beforeMs,afterMs].every(Number.isInteger)||capacity<1||capacity>128||beforeMs<0||afterMs<0||beforeMs+afterMs>retentionMs||retentionMs>3600000||retentionMs<1)throw Error('Invalid bounds');
    Object.defineProperties(this,{clock:{value:clock},capacity:{value:capacity},retentionMs:{value:retentionMs},beforeMs:{value:beforeMs},afterMs:{value:afterMs}});this.#started=this.#time();
  }
  #time(){const n=this.clock();if(!Number.isSafeInteger(n)||n<0||n>8640000000000000||this.#lastNow!==undefined&&n<this.#lastNow)throw Error('Clock unavailable');this.#lastNow=n;return n;}
  #prune(now){const evicted=this.#events.filter(x=>now-x.time>=this.retentionMs);if(evicted.length)this.#droppedThrough=Math.max(this.#droppedThrough,...evicted.map(x=>x.time));this.#events=this.#events.filter(x=>now-x.time<this.retentionMs);this.#incidents=this.#incidents.filter(x=>now-x.detected<this.retentionMs);}
  ingest({event_id,at,kind,generation=null,source_id=null,source_epoch=null}){
    const now=this.#time();this.#prune(now);
    if(!uuid.test(event_id)||!Number.isSafeInteger(at)||at>now||now-at>=this.retentionMs||!kinds.has(kind)||generation!==null&&(!Number.isInteger(generation)||generation<1||generation>1000000)||source_id===null&&source_epoch!==null||source_id!==null&&!/^[0-9a-f]{64}$/.test(source_id)||source_id!==null&&(!Number.isInteger(source_epoch)||source_epoch<1))return false;
    if(this.#events.some(x=>x.event_id===event_id))return false;
    this.#events.push({event_id,time:at,kind,generation,source_id,source_epoch});this.#events.sort((a,b)=>a.time-b.time||a.event_id.localeCompare(b.event_id));
    while(this.#events.length>this.capacity)this.#droppedThrough=Math.max(this.#droppedThrough,this.#events.shift().time);
    return true;
  }
  detect({event_id,incident_id=crypto.randomUUID(),correlation_id=crypto.randomUUID()}){
    const now=this.#time();this.#prune(now);if(!uuid.test(incident_id)||!uuid.test(correlation_id))throw Error('Invalid identifier');
    const event=this.#events.find(x=>x.event_id===event_id);if(!event)throw Error('Detection event unavailable');
    const existing=this.#incidents.find(x=>x.incident_id===incident_id);if(existing)return this.report(incident_id);
    const related=event.source_id===null?null:this.#incidents.findLast(x=>x.source_id===event.source_id&&x.source_epoch===event.source_epoch&&event.time>=x.detected-this.beforeMs&&event.time<=x.detected+this.afterMs);
    if(related)return this.report(related.incident_id);
    if(this.#incidents.length>=100)throw Error('Incident capacity');
    this.#incidents.push({incident_id,correlation_id,event_id,detected:event.time,source_id:event.source_id,source_epoch:event.source_epoch});return this.report(incident_id);
  }
  report(id){
    const now=this.#time();this.#prune(now);const incident=this.#incidents.find(x=>x.incident_id===id);if(!incident)throw Error('Incident unavailable');
    const from=incident.detected-this.beforeMs,to=incident.detected+this.afterMs;
    const related=this.#events.filter(x=>x.time>=from&&x.time<=to&&(incident.source_id===null?x.event_id===incident.event_id:x.source_id===incident.source_id&&x.source_epoch===incident.source_epoch));
    const missing_before=this.#started>from||this.#droppedThrough>=from,missing_after=now<to;
    return {incident_id:incident.incident_id,correlation_id:incident.correlation_id,detected_at:iso(incident.detected),window_from:iso(from),window_to:iso(to),status:'detected',collection_status:missing_after?'collecting':missing_before?'partial':'complete',missing_before,missing_after,event_count:related.length,events:related.map((e,index)=>({sequence:index+1,at:iso(e.time),kind:e.kind,generation:e.generation})),source_tracking:incident.source_id===null?'unavailable':'synthetic_pseudonym',first_seen:related.length?iso(related[0].time):null,last_seen:related.length?iso(related.at(-1).time):null};
  }
}

