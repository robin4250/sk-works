// Review-only internal adapter. Requires a separately provisioned privileged
// server pool and verified bearer port. No public RPC/grant or credential store.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const denied=()=>Error('apple_successor_handoff_unavailable');
export function createSuccessorDBPorts({enabled=false,reviewed=false,passwordSuccessorReviewed=false,pool,authenticateExactBearer,now=Date.now}={}){
 let binding=null,holdBinding=null,attempted=false,passwordAttempted=false,passwordBinding=null;
 const ready=()=>enabled===true&&reviewed===true&&typeof pool?.connect==='function'&&typeof authenticateExactBearer==='function';
 async function transaction(work){
  if(!ready())throw denied();const db=await pool.connect();
  try{
   await db.query('begin');
   await db.query("set local lock_timeout='3s'");await db.query("set local statement_timeout='5s'");
   // The internal SQL accepts only the privileged server context. User identity
   // is independently verified, then passed as bounded SQL parameters.
   await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);
   const value=await work(db);await db.query('commit');return value;
  }catch{try{await db.query('rollback');}catch{}throw denied();}
  finally{db.release();}
 }
 async function verifiedClaims(exactBearer){
  if(!ready()||typeof exactBearer!=='string'||!exactBearer||exactBearer.length>16384)throw denied();
  const verified=await authenticateExactBearer(exactBearer),c=verified?.claims,at=Math.floor(now()/1000);
  if(!Number.isSafeInteger(at)||!c||c.role!=='authenticated'||!uuid.test(c.sub??'')||!uuid.test(c.session_id??'')||
   !Number.isSafeInteger(c.exp)||c.exp<=at||verified.user?.id!==c.sub||verified.user.is_anonymous===true)throw denied();
  return c;
 }
 return Object.freeze({
  async beginPasswordSuccessorForBearer({exactBearer,subject,token_sha256}){
   if(passwordSuccessorReviewed!==true||passwordAttempted||typeof subject!=='string'||!/^[A-Za-z0-9._-]{1,255}$/.test(subject)||!/^[a-f0-9]{64}$/.test(token_sha256??''))throw denied();
   passwordAttempted=true;const c=await verifiedClaims(exactBearer);
   const row=await transaction(async db=>(await db.query('select apple_native_enrollment_private.begin_password_successor($1,$2,$3,$4) r',[c.sub,c.session_id,subject,token_sha256])).rows[0]?.r);
   if(!row||!uuid.test(row.intent_id??'')||row.actor_id!==c.sub||row.original_session_id!==c.session_id||row.subject!==subject||row.token_sha256!==token_sha256)throw denied();
   passwordBinding=Object.freeze({intent_id:row.intent_id,actor_id:c.sub,original_session_id:c.session_id});return row;
  },
  async reservePasswordSuccessorForBearer({intent_id,exactBearer}){
   if(passwordSuccessorReviewed!==true||!passwordBinding||intent_id!==passwordBinding.intent_id)throw denied();
   const expected=passwordBinding;passwordBinding=null;
   const c=await verifiedClaims(exactBearer);
   if(c.sub!==expected.actor_id||c.session_id===expected.original_session_id)throw denied();
   const row=await transaction(async db=>(await db.query('select apple_native_enrollment_private.reserve_password_successor($1,$2,$3,$4) r',[expected.intent_id,expected.actor_id,expected.original_session_id,c.session_id])).rows[0]?.r);
   if(!row||!uuid.test(row.request_id??'')||row.actor_id!==c.sub||row.session_id!==c.session_id||row.original_session_id!==expected.original_session_id||row.intent_id!==expected.intent_id||row.status!=='reserved')throw denied();
   return row;
  },
  async claimReservedForBearer({request_id,exactBearer}){
   if(attempted)throw denied();attempted=true;binding=null;if(!ready()||!uuid.test(request_id??'')||typeof exactBearer!=='string'||!exactBearer||exactBearer.length>16384)throw denied();
   let verified;try{verified=await authenticateExactBearer(exactBearer);}catch{throw denied();}
   const c=verified?.claims;
   const at=Math.floor(now()/1000);
   if(!Number.isSafeInteger(at)||!c||c.role!=='authenticated'||!uuid.test(c.sub??'')||!uuid.test(c.session_id??'')||
    !Number.isSafeInteger(c.exp)||c.exp<=at||verified.user?.id!==c.sub||verified.user.is_anonymous===true)throw denied();
   const row=await transaction(async db=>(await db.query('select apple_native_enrollment_private.claim_successor_attempt($1,$2,$3) r',[request_id,c.sub,c.session_id])).rows[0]?.r);
   if(!row||row.request_id!==request_id||row.actor_id!==c.sub||row.session_id!==c.session_id||row.status!=='reserved')throw denied();
   binding=Object.freeze({request_id,actor_id:c.sub,original_session_id:c.session_id,snapshot_sha256:row.snapshot_sha256});
   holdBinding=binding;
   // COMMIT has succeeded before a caller can perform external Auth linking.
   return row;
  },
  async completeWithSuccessor(info){
   if(!binding||info.request_id!==binding.request_id||info.actor_id!==binding.actor_id||info.original_session_id!==binding.original_session_id||
    info.snapshot_sha256!==binding.snapshot_sha256||!uuid.test(info.successor_session_id??''))throw denied();
   const expected=binding;binding=null;
   return transaction(async db=>(await db.query('select apple_native_enrollment_private.complete_with_successor($1,$2,$3,$4,$5,$6,$7) r',
    [expected.request_id,expected.actor_id,expected.original_session_id,info.successor_session_id,info.subject,info.token_sha256,expected.snapshot_sha256])).rows[0]?.r);
  },
  async holdSubject(request_id){
   const expected=holdBinding;holdBinding=null;
   if(!expected||request_id!==expected.request_id)throw denied();
   // The existing SQL only changes a still-reserved request. A committed
   // completion is never rewritten even if its response was lost.
   return transaction(async db=>(await db.query('select public.hold_apple_native_subject($1,$2,$3) r',
    [expected.request_id,expected.actor_id,expected.original_session_id])).rows[0]?.r);
  },
 });
}

