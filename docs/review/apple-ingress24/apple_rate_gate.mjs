// Contract only: trusted shared limiter must atomically count across instances.
// actorId is selected by server-side verified authentication, never request JSON.
export function createAppleEnrollmentRateGate({enabled=false, take}={}) {
 const ready=enabled===true && typeof take==='function';
 return Object.freeze({ready, async check({actorId,sessionId}) {
  if(!ready || typeof actorId!=='string' || typeof sessionId!=='string' ||
   !/^[0-9a-f-]{36}$/i.test(actorId) || !/^[0-9a-f-]{36}$/i.test(sessionId)) throw Error('apple_rate_gate_unavailable');
  let result;try {result=await take({actorId,sessionId});}catch{throw Error('apple_rate_gate_unavailable');}
  if(!result || result.allowed!==true || result.durable!==true) throw Error('apple_rate_gate_unavailable');
 }});
}
