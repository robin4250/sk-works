import assert from 'node:assert/strict';
export const actor='10000000-0000-0000-0000-000000000001';
export const company='30000000-0000-0000-0000-000000000001';
export const sid='80000000-0000-0000-0000-000000000001';
// Synthetic Auth /user fixture verifies this token. Not real GoTrue evidence.
export const token='fixture.'+Buffer.from(JSON.stringify({sub:actor,session_id:sid,role:'authenticated',exp:4102444800})).toString('base64url')+'.fixture';
export function contextResponse(options) {
 const body=JSON.parse(options.body);
 assert.deepEqual(body,{p_actor:actor,p_session:sid,p_company:company});
 return Response.json({version:1,actor_id:actor,session_id:sid,company_id:company,role:'owner'});
}
export function bindFixtureHandler(raw) {
 return async req=>{
  if(req.headers.get('authorization')!=='Bearer fixture-user')return raw(req);
  const body=await req.json(),headers=new Headers(req.headers);
  headers.set('authorization','Bearer '+token);
  return raw(new Request(req,{headers,body:JSON.stringify({...body,...(body.workerId?{expectedPhone:'07000000000'}:{}),companyId:company,sessionId:sid})}));
 };
}
