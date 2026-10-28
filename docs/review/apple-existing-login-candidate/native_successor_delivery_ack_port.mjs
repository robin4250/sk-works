// Internal OFF adapter. No HTTP route, token retransmission or adoption claim.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const validUUID=value=>typeof value==='string'&&uuid.test(value);
const denied=()=>Error('apple_successor_reconciliation_unavailable');
function data(value,keys){
 if(!value||typeof value!=='object'||![null,Object.prototype].includes(Object.getPrototypeOf(value)))throw denied();
 const fields=Object.getOwnPropertyDescriptors(value),names=Reflect.ownKeys(fields);
 if(names.length!==keys.length||names.some(k=>!keys.includes(k)))throw denied();
 const result={};for(const key of keys){const d=fields[key];if(!d||!Object.hasOwn(d,'value'))throw denied();result[key]=d.value;}
 return result;
}
export function createSuccessorDeliveryAckPorts({enabled=false,reviewed=false,pool,authenticateExactBearer,now=Date.now}={}){
 const connect=typeof pool?.connect==='function'?pool.connect.bind(pool):null;
 const authenticate=authenticateExactBearer;
 const ready=enabled===true&&reviewed===true&&connect&&typeof authenticate==='function'&&typeof now==='function';
 const fresh=exp=>{const at=Math.floor(now()/1000);if(!Number.isSafeInteger(at)||!Number.isSafeInteger(exp)||exp<=at)throw denied();};
 async function invoke(input,acknowledge){
  let args,verified;
  try{
   if(!ready)throw denied();
   args=data(input,['request_id','exactBearer']);
   if(!validUUID(args.request_id)||typeof args.exactBearer!=='string'||!args.exactBearer||
    args.exactBearer.length>16384||/\s/.test(args.exactBearer))throw denied();
   const result=await authenticate(args.exactBearer),c=result?.claims,u=result?.user;
   // Snapshot scalars immediately after trusted Auth validation, before any
   // pool/SQL awaits. Never accept successor metadata from the caller.
   verified=Object.freeze({actor:c?.sub,sid:c?.session_id,exp:c?.exp,role:c?.role,
    user:u?.id,anonymous:u?.is_anonymous===true});
   if(verified.role!=='authenticated'||!validUUID(verified.actor)||!validUUID(verified.sid)||
    verified.user!==verified.actor||verified.anonymous)throw denied();
   fresh(verified.exp);
  }catch{throw denied();}
  let db,query,release;
  try{
   db=await connect();query=db.query.bind(db);release=db.release.bind(db);
   await query('begin');
   await query("set local lock_timeout='3s'");await query("set local statement_timeout='5s'");
   fresh(verified.exp);
   await query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role',
    sub:verified.actor,session_id:verified.sid,exp:verified.exp})]);
   const name=acknowledge?'acknowledge_successor_possession':'successor_delivery_status';
   const raw=(await query(`select apple_native_enrollment_private.${name}($1,$2,$3) r`,
    [args.request_id,verified.actor,verified.sid])).rows[0]?.r;
   const result=data(raw,['schema','request_id','status','retry_allowed','application_adoption_confirmed']);
   if(result.schema!==1||result.request_id!==args.request_id||result.retry_allowed!==false||
    result.application_adoption_confirmed!==false||
    !['server_completed','successor_possession_recorded'].includes(result.status)||
    acknowledge&&result.status!=='successor_possession_recorded')throw denied();
   fresh(verified.exp);
   await query('commit');
   return Object.freeze({...result});
  }catch{if(query){try{await query('rollback');}catch{}}throw denied();}
  finally{if(release){try{release();}catch{throw denied();}}}
 }
 return Object.freeze({
  status:input=>invoke(input,false),
  acknowledge:input=>invoke(input,true),
 });
}
