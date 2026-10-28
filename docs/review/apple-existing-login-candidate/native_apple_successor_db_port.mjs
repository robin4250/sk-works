// Review-only internal adapter. Requires a separately provisioned privileged
// server pool and verified bearer port. No public RPC/grant or credential store.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const denied=()=>Error('apple_successor_handoff_unavailable');
export function createSuccessorDBPorts({enabled=false,reviewed=false,pool,authenticateExactBearer,now=Date.now}={}){
 let binding=null,attempted=false;
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
 return Object.freeze({
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
 });
}
