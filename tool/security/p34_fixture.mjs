// Synthetic fixture only. Reuses the exact existing setup, not production data.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const p=path.join(root,'tool/security/personnel_write/verify.mjs');
const bytes=fs.readFileSync(p);
if(crypto.createHash('sha256').update(bytes).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('Existing fixture source drift');
let source=bytes.toString();
const marker='const baseline=await capsule();';
if(source.split(marker).length!==2)throw Error('Fixture setup anchor drift');
source=source.split(marker)[0];
for(const name of ['20261016104441_personnel_direct_read_permission_guard.sql','20261016113335_personnel_legacy_read_permission_guard.sql']){
 const line="await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/"+name+"'),'utf8'));";
 if(source.split(line).length!==2)throw Error('Existing migration setup anchor drift');
 source=source.replace(line,'');
}
source=source.replace("const here=path.dirname(fileURLToPath(import.meta.url));","const here="+JSON.stringify(path.dirname(p))+";");
const result=spawnSync('python3',[path.join(root,'tool/security/p34_atomic.py'),root],{encoding:'utf8',timeout:10000});
if(result.status!==0)throw Error('Composition failed: '+result.stderr);
source+='\nconst atomic='+JSON.stringify(result.stdout)+';\n';
source+=`
const snapshot=async()=>({
 capsule:await capsule(),
 definitions:(await db.query("select oid::text,pg_get_functiondef(oid) definition from pg_proc where oid in ('private.employee_personnel_rows()'::regprocedure,'private.can_edit_worker_personnel(uuid)'::regprocedure) order by oid")).rows
});
const original=await snapshot();
const originalPolicies=(await db.query("select * from pg_policies where schemaname='public' and tablename in ('worker_personnel_profiles','worker_family_members') order by policyname")).rows;
const late=atomic.slice(0,-'commit;\\n'.length)+"do $$begin raise exception 'synthetic late failure';end$$;\\ncommit;\\n";
await assert.rejects(db.exec(late),/synthetic late failure/);await db.exec('rollback');
assert.deepEqual(await snapshot(),original,'late failure rolls all 4 target objects/data/ACL/IDs back');
await db.exec(atomic);
const applied=await snapshot();
assert.deepEqual(applied.capsule.rows,original.capsule.rows,'no business or identity/company/master/provider changes');
assert.deepEqual(applied.capsule.acl,original.capsule.acl,'table/column grants and RLS unchanged');
for(const key of ['managerOff','managerOn','owner','admin','viewer','self','outsider','deleted']){
 await actor(actors[key]);
 const allowed=['managerOn','owner','admin','viewer','self'].includes(key);
 const count=(await db.query('select count(*)::int n from worker_personnel_profiles where worker_id=$1',[W])).rows[0].n;
 assert.equal(count,allowed?1:0,key+' direct profile');
 const family=(await db.query('select count(*)::int n from worker_family_members where worker_id=$1',[W])).rows[0].n;
 assert.equal(family,allowed?1:0,key+' direct family');
 const can=(await db.query('select private.can_edit_worker_personnel($1) b',[W])).rows[0].b;
 assert.equal(can,['managerOn','owner','admin','self'].includes(key),key+' write helper');
 if(['managerOn','owner','admin'].includes(key))assert.ok(Array.isArray((await db.query('select public.employee_personnel_rows() p')).rows[0].p));
 else await assert.rejects(db.query('select public.employee_personnel_rows()'),e=>e.code==='42501');
}
await db.exec('reset role');
const ident=s=>'"'+s.replaceAll('"','""')+'"';
await db.exec('begin');
for(const row of original.definitions)await db.exec(row.definition);
for(const p of originalPolicies){
 await db.exec('drop policy '+ident(p.policyname)+' on public.'+ident(p.tablename));
 let sql='create policy '+ident(p.policyname)+' on public.'+ident(p.tablename)+' as '+p.permissive+' for '+p.cmd+' to '+p.roles.map(ident).join(',');
 if(p.qual)sql+=' using ('+p.qual+')';if(p.with_check)sql+=' with check ('+p.with_check+')';await db.exec(sql);
}
await db.exec('commit');assert.deepEqual(await snapshot(),original,'selected rollback restores full original snapshot');
await actor(actors.managerOff);assert.equal((await db.query('select count(*)::int n from worker_personnel_profiles where worker_id=$1',[W])).rows[0].n,1,'rollback restores old leak: distribution stays HOLD');
await db.exec('reset role');await db.exec(atomic);
assert.deepEqual(await snapshot(),applied,'reapply exact output');
await db.close();console.log('PASS P34: composition, 4-object late rollback, role matrix, identity/data/ACL preservation, exact original restoration and reapply. Native actual backup restoration NOT proven.');
`;
await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
