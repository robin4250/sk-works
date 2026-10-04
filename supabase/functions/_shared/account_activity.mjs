// Tracks server-side side effects across separate HTTP/DB transactions.
// Finish only after all remote effects have been acknowledged. An ambiguous
// failure deliberately leaves the activity present, blocking account erasure.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function serverAccountActivity(rpc) {
 const invoke=async(name,args)=>{
  try{return await rpc(name,args);}catch{throw Error('account_activity_unavailable');}
 };
 return {
  async begin(userId,purpose){
   if(!uuid.test(userId??'') || !['support-contact','create-employee-invite'].includes(purpose))
    throw Error('account_activity_unavailable');
   const id=await invoke('begin_account_server_activity',{p_user:userId,p_purpose:purpose});
   if(typeof id!=='string' || !uuid.test(id)) throw Error('account_activity_unavailable');
   return id;
  },
  async finish(userId,id){
   if(!uuid.test(userId??'') || !uuid.test(id??'')) throw Error('account_activity_unavailable');
   if(await invoke('finish_account_server_activity',{p_user:userId,p_id:id})!==true)
    throw Error('account_activity_unavailable');
  },
 };
}
