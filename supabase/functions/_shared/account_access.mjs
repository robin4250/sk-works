// Pass only a user ID obtained from verified Auth, never from a request body.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function serverAccountAccess(rpc) {
 return async userId=>{
  if(!uuid.test(userId??'')) throw Error('account_access_unavailable');
  let result;
  try { result=await rpc('account_server_access_allowed',{p_user:userId}); }
  catch { throw Error('account_access_unavailable'); }
  if(typeof result!=='boolean') throw Error('account_access_unavailable');
  return result;
 };
}
