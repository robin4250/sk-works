// Test-only composition of the existing synthetic write fixture and staged resolver.
// No project connection, production data, migration deployment, or altered product SQL.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const source=fs.readFileSync(path.join(here,'verify.mjs'),'utf8');
const boundary='const baseline=await capsule();';
if(source.split(boundary).length!==2)throw Error('Existing fixture setup boundary drift');
let setup=source.slice(0,source.indexOf(boundary));
const locationBoundary='const here=path.dirname(fileURLToPath(import.meta.url));';
if(setup.split(locationBoundary).length!==2)throw Error('Existing fixture location boundary drift');
setup=setup.replace(locationBoundary,'const here='+JSON.stringify(here)+';');
// The reused write test excludes the helper body while testing its replacement.
// Here all guards are already installed, so preserve that body too.
const helperBoundary="case when n.nspname='private' and p.proname='can_edit_worker_personnel' then null else pg_get_functiondef(p.oid) end definition";
if(setup.split(helperBoundary).length!==2)throw Error('Existing fixture helper snapshot boundary drift');
setup=setup.replace(helperBoundary,'pg_get_functiondef(p.oid) definition');
const checks=String.raw`
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
const before=await capsule();
await db.exec(fs.readFileSync(path.join(root,'tool/staged/worker_personnel_completed_notification_target.sql'),'utf8'));
const after=await capsule();
assert.deepEqual(after.rows,before.rows);
assert.deepEqual(after.policies,before.policies);
assert.deepEqual(after.acl,before.acl);
assert.deepEqual(after.functions.filter(x=>x.proname!=='worker_personnel_completed_notification_target'),before.functions);
const notice=id(201),request=id(202);
const resolve=async()=>(await db.query('select public.worker_personnel_completed_notification_target($1,$2,$3) target',[C,notice,request])).rows[0].target;
let cases=0;
// Observe actual direct/legacy read behavior while the resolver and all guards coexist.
for(const [key,count]of Object.entries({managerOff:0,owner:2,self:1,viewer:1})){
 await db.exec('begin');await actor(actors[key]);
 assert.deepEqual(await ownCounts(),[count,count],key+' same-database direct address/family scope');
 if(key==='owner')assert.ok((await db.query('select public.employee_personnel_rows() payload')).rows[0].payload.length>0);
 else await assert.rejects(db.query('select public.employee_personnel_rows()'),e=>e.code==='42501',key+' legacy company-list scope');
 await db.exec('rollback;reset role');assert.deepEqual(await capsule(),after);
}

async function probe(key,allowed,mutation=''){
 await db.exec('begin');
 await db.query("insert into worker_personnel_change_requests(id,company_id,worker_id,requested_by,proposed,required_approvals,status,resolved_at)values($1,$2,$3,$4,$5,1,'approved',now())",[request,C,W,actors[key],JSON.stringify({secret:'must not return'})]);
 await db.query("insert into app_notifications(id,company_id,recipient_user_id,action_key,action_id)values($1,$2,$3,'worker_personnel_change_completed',$4)",[notice,C,actors[key],request]);
 if(mutation)await db.exec(mutation);
 await actor(actors[key]);
 if(allowed)assert.deepEqual(await resolve(),{company_id:C,request_id:request,worker_id:W,status:'approved'});
 else await assert.rejects(resolve(),e=>e.code==='42501'&&e.message==='通知の対象を確認できません');
 await db.exec('rollback;reset role');
 assert.deepEqual(await capsule(),after,'Resolver probe must preserve all business/protected data, functions and ACLs');
 cases++;
}
for(const key of ['owner','admin','managerOn','viewer','self'])await probe(key,true);
for(const key of ['managerOff','employee','outsider','deleted'])await probe(key,false);
await probe('managerOn',false,"update member_feature_permissions set can_manage_people=false where user_id='"+actors.managerOn+"'");
await probe('managerOn',false,"delete from company_members where user_id='"+actors.managerOn+"'");
await probe('managerOn',false,"insert into private.account_deletion_access_restrictions values('"+actors.managerOn+"')");
await probe('viewer',false,"update workers set status='inactive' where id='"+W+"'");
await probe('self',true,"update member_feature_permissions set can_manage_people=false where user_id='"+actors.self+"'");
// Actual save -> approval -> emitted notification, without synthetic notification insertion.
for(const key of ['self','managerOn']){
 await db.exec('begin');
 const original=(await db.query('select private.worker_personnel_payload($1) payload',[W])).rows[0].payload;
 await actor(actors[key]);
 const submitted=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) payload',[W,JSON.stringify({...original,address:'synthetic approved integration'})])).rows[0].payload;
 assert.equal(submitted.status,'pending');
 await actor(actors.owner);
 assert.equal((await db.query('select public.decide_worker_personnel_change($1,true) payload',[submitted.request_id])).rows[0].payload.status,'approved');
 await db.exec('reset role');
 const emitted=(await db.query("select id,action_id from app_notifications where action_key='worker_personnel_change_completed' and recipient_user_id=$1",[actors[key]])).rows;
 assert.equal(emitted.length,1);assert.equal(emitted[0].action_id,submitted.request_id);
 await actor(actors[key]);
 assert.deepEqual((await db.query('select public.worker_personnel_completed_notification_target($1,$2,$3) target',[C,emitted[0].id,submitted.request_id])).rows[0].target,{company_id:C,request_id:submitted.request_id,worker_id:W,status:'approved'});
 await db.exec('rollback;reset role');assert.deepEqual(await capsule(),after);
 cases++;
}
await db.close();
console.log('PASS: '+cases+' staged notification resolver cases with exact direct-read, legacy-read and write guards in one synthetic PGlite database; resolver-only function additions; original business/identity/source/ACL/RLS invariants preserved.');
`;
await import('data:text/javascript;base64,'+Buffer.from(setup+checks).toString('base64'));
