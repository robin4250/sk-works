// Isolation candidate only. Never expose the SQL connection to a client and do
// not deploy with a privileged pool. The caller supplies a transaction factory;
// production authentication, least privilege and operator isolation remain open.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const reject=()=>{throw Error('apple_recovery_unavailable');};
const reason='本人のApple連携の保留状態を安全に照合';
function args(value){if(!value||![value.request_id,value.actor_id,value.session_id].every(x=>uuid.test(x??'')))reject();return [value.request_id,value.actor_id,value.session_id];}
export function createSelfRecoveryPostgresPort({enabled=false,operatorBoundaryReviewed=false,transaction}={}){
 if(typeof transaction!=='function')reject();
 async function run(fn){if(enabled!==true||operatorBoundaryReviewed!==true)reject();try{return await transaction(fn);}catch{reject();}}
 return Object.freeze({
  async readOwnRequest(input){const a=args(input);return run(async q=>{
   await q('select apple_native_enrollment_private.root_operator()');
   const live=(await q('select apple_native_enrollment_private.context($1,$2) c',[a[1],a[2]])).rows[0]?.c;
   if(!live||live.account_allowed!==true)reject();
   const row=(await q('select request_id,actor_id,status from apple_native_enrollment_private.requests where request_id=$1 and actor_id=$2',[a[0],a[1]])).rows[0];
   if(!row||!['held','cancelled','completed'].includes(row.status))reject();
   return Object.freeze({request_id:row.request_id,actor_id:row.actor_id,status:row.status});
  });},
  async getOrCreateRecoveryCommand(input){const a=args(input);return run(async q=>{
   const row=(await q('select apple_native_enrollment_private.self_recovery_command($1,$2,$3) c',a)).rows[0]?.c;
   if(!row||row.request_id!==a[0]||row.actor_id!==a[1]||row.session_id!==a[2]||!uuid.test(row.command_id??''))reject();return row;
  });},
  async reconcileOwnHeld(input){const a=args(input);if(!uuid.test(input.command_id??''))reject();return run(async q=>{
   // Read the append-only command without taking the request row lock. The
   // original reconciliation routine owns its established Auth lock order.
   await q('select apple_native_enrollment_private.root_operator()');
   // The existing reconcile routine returns a recorded command before its own
   // live-context check. Check the session again even on idempotent replay;
   // production also needs a proven revocation lock around this transaction.
   const live=(await q('select apple_native_enrollment_private.context($1,$2) c',[a[1],a[2]])).rows[0]?.c;
   if(!live||live.account_allowed!==true)reject();
   const c=(await q('select command_id from apple_native_enrollment_private.self_recovery_commands where request_id=$1 and actor_id=$2 and session_id=$3',a)).rows[0];
   if(!c||c.command_id!==input.command_id)reject();
   const v=(await q('select apple_native_enrollment_private.reconcile_request($1,$2,$3,$4) r',[input.command_id,a[0],a[2],reason])).rows[0]?.r;
   if(!v||v.request_id!==a[0])reject();return v;
  });},
 });
}
