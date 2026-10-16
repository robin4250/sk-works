import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// Called ONLY by the exact-hash original local GoTrue fixture, through its
// loopback/origin-checked request helper. No direct network, credentials or UI.
export async function verifySessionLifecycle({request,db,password,claims,guardedSessions}) {
 const count=async uid=>(await db.query('select count(*)::int n from auth.sessions where user_id=$1',[uid])).rows[0].n;
 const exists=async sid=>(await db.query('select count(*)::int n from auth.sessions where id=$1',[sid])).rows[0].n;
 async function json(response,status){assert.equal(response.status,status,'Lifecycle HTTP status');return response.json();}
 async function login(email){const data=await json(await request('/auth/v1/token?grant_type=password',{body:{email,password}}),200);assert.ok(typeof data.access_token==='string'&&typeof data.refresh_token==='string');return data;}
 async function refresh(token){return json(await request('/auth/v1/token?grant_type=refresh_token',{body:{refresh_token:token}}),200);}
 async function rejectedRefresh(token){
  const response=await request('/auth/v1/token?grant_type=refresh_token',{body:{refresh_token:token}});
  assert.ok(response.status===400||response.status===401,'Revoked refresh must be rejected');
  const result=await response.json();assert.equal(result.access_token,undefined);assert.equal(result.refresh_token,undefined);assert.equal(result.user,undefined);
 }
 async function identity(uid){return (await db.query(`select jsonb_build_object('user',(select jsonb_build_object('id',id,'email',email,'phone',phone,'app_metadata',raw_app_meta_data,'user_metadata',raw_user_meta_data) from auth.users where id=$1),'identities',(select jsonb_agg(jsonb_build_object('user_id',user_id,'provider',provider,'provider_id',provider_id,'identity_data',identity_data) order by provider,provider_id) from auth.identities where user_id=$1)) v`,[uid])).rows[0].v;}
 const created=await json(await request('/auth/v1/admin/users',{service:true,body:{email:`session-${randomUUID()}@example.invalid`,password,email_confirm:true}}),200);
 assert.equal(await count(created.id),0);
 const preserved=[];for(const session of guardedSessions){const c=claims(session.access_token);assert.equal(await exists(c.session_id),1);preserved.push(c.session_id);}
 const first=await login(created.email);assert.equal(first.user.id,created.id);const beforeIdentity=await identity(created.id);const sidA=claims(first.access_token).session_id;assert.ok(sidA);assert.equal(await count(created.id),1);
 // Drop/reconstruct only a serialized refresh-token envelope in memory. This is
 // the SERVER half of SDK rehydration, not a Flutter/native secure-storage test.
 const rehydrated=JSON.parse(JSON.stringify({refresh_token:first.refresh_token}));
 const restarted=await refresh(rehydrated.refresh_token);assert.equal(restarted.user.id,created.id);assert.equal(claims(restarted.access_token).session_id,sidA);assert.equal(await count(created.id),1);
 assert.equal(await exists(sidA),1);
 const second=await login(created.email),sidB=claims(second.access_token).session_id;assert.ok(sidB&&sidB!==sidA);assert.equal(await count(created.id),2);
 // gotrue2.27.2 Dart signOut() default is LOCAL, explicitly forwarded by SDK.
 assert.equal((await request('/auth/v1/logout?scope=local',{token:restarted.access_token})).status,204);
 assert.equal(await exists(sidA),0);assert.equal(await exists(sidB),1);assert.equal(await count(created.id),1);
 await rejectedRefresh(first.refresh_token);await rejectedRefresh(restarted.refresh_token);
 assert.equal(await exists(sidB),1,'Other device session survives app-default local signout');
 const secondRefreshed=await refresh(second.refresh_token);assert.equal(claims(secondRefreshed.access_token).session_id,sidB);assert.equal(await count(created.id),1);
 // Explicit global revocation is a separate server capability; not app default.
 assert.equal((await request('/auth/v1/logout?scope=global',{token:secondRefreshed.access_token})).status,204);
 assert.equal(await count(created.id),0);await rejectedRefresh(second.refresh_token);await rejectedRefresh(secondRefreshed.refresh_token);
 const legitimate=await login(created.email),sidC=claims(legitimate.access_token).session_id;assert.ok(sidC&&sidC!==sidA&&sidC!==sidB);assert.equal(legitimate.user.id,created.id);assert.equal(await count(created.id),1);
 assert.equal((await request('/auth/v1/user',{token:legitimate.access_token,method:'GET'})).status,200);
 // Identity/provider ownership is stable; successful-login timestamps are not.
 assert.deepEqual(await identity(created.id),beforeIdentity);
 for(const sid of preserved)assert.equal(await exists(sid),1,'Original master/admin/other sessions remain alive');
 assert.equal((await request('/auth/v1/logout?scope=local',{token:legitimate.access_token})).status,204);assert.equal(await count(created.id),0);
 console.log('PASS actual GoTrue lifecycle: password login, refresh-token rehydration with the same server session, app-default LOCAL logout revokes that refresh chain and preserves another session, explicit GLOBAL revocation rejects its old chain, legitimate password relogin creates a new session; original identity/provider/master/admin sessions preserved.');
 console.log('LIMIT lifecycle: HTTP server semantics only, not real Dart process restart, iPhone persistence, Face ID, OAuth or instant access-JWT invalidation. Rotation reuse grace is not treated as a failure; revoked refresh chains must be rejected.');
}
