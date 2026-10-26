import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root=process.env.SKO_SECURITY_CHECKOUT_ROOT??process.cwd();
const here=dirname(fileURLToPath(import.meta.url));
const fixture=join(root,'tool/security/personnel_write/verify.mjs');
let source=await readFile(fixture,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('reviewed_personnel_bootstrap_drift');
const marker='const baseline=await capsule();';
if(source.split(marker).length!==2)throw Error('bootstrap_anchor_drift');
source=source.split(marker)[0];
for(const name of ['20261016104441_personnel_direct_read_permission_guard.sql','20261016113335_personnel_legacy_read_permission_guard.sql']){
 const line="await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/"+name+"'),'utf8'));";
 if(source.split(line).length!==2)throw Error('bootstrap_migration_anchor_drift');
 source=source.replace(line,'');
}
source=source.replace("const here=path.dirname(fileURLToPath(import.meta.url));",'const here='+JSON.stringify(dirname(fixture))+';');
const folder=await mkdtemp(join(tmpdir(),'sko-personnel-current-guard-'));
const tail=String.raw`
const {writeFile,readFile}=await import('node:fs/promises');
const {execFileSync}=await import('node:child_process');
const folder=process.env.SKO_PERSONNEL_GUARD_FOLDER,generator=process.env.SKO_PERSONNEL_GUARD_GENERATOR;
let checks=0;
const eq=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
const collect=async()=>{
 const tables=(await db.query("select c.relname as relation,c.oid::text as oid,pg_get_userbyid(c.relowner)as owner,c.relacl::text as acl,c.relrowsecurity as rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'and c.relkind='r'and c.relname in('worker_personnel_profiles','worker_family_members')order by c.relname")).rows;
 const policies=(await db.query("select tablename as table,policyname as name,permissive,to_jsonb(roles)as roles,cmd,qual,with_check from pg_policies where schemaname='public'and tablename in('worker_personnel_profiles','worker_family_members')order by tablename,policyname")).rows;
 const routines=(await db.query("select p.oid::regprocedure::text as signature,p.oid::text as oid,pg_get_functiondef(p.oid)as definition,pg_get_userbyid(p.proowner)as owner,p.proacl::text as acl,p.proconfig as config,p.prosecdef as security_definer,p.provolatile as volatility from pg_proc p where p.oid in('private.employee_personnel_rows()'::regprocedure,'public.employee_personnel_rows()'::regprocedure,'private.can_edit_worker_personnel(uuid)'::regprocedure,'public.save_worker_personnel_profile(uuid,jsonb)'::regprocedure,'private.account_access_allowed()'::regprocedure,'private.has_company_feature(uuid,text)'::regprocedure,'private.personnel_view_allowed(uuid)'::regprocedure)order by p.oid")).rows;
 // regprocedure can omit public under the default path; pin explicit names.
 for(const r of routines)if(!r.signature.includes('.'))r.signature='public.'+r.signature;
 return [{snapshot:{tables,policies,routines}}];
};
const original=await collect();await writeFile(folder+'/before.json',JSON.stringify(original));
async function prepare(post){
 const args=[generator,'--source-root',root,'--before',folder+'/before.json','--output',folder+'/candidate.sql'];
 if(post){await writeFile(folder+'/post.json',JSON.stringify(post));args.push('--post',folder+'/post.json');}
 execFileSync('python3',args,{stdio:'pipe'});return await readFile(folder+'/candidate.sql','utf8');
}
const baseline=await capsule();const sql=await prepare();
eq((sql.match(/^begin;$/gm)??[]).length,1,'fresh wrapper is one transaction');
await db.exec('create policy unrelated_policy_drift on worker_personnel_profiles for select to authenticated using(false)');
await assert.rejects(db.exec(sql),/personnel_current_policies_drift/);checks++;await db.exec('rollback;drop policy unrelated_policy_drift on worker_personnel_profiles');
eq(await collect(),original,'unexpected policy drift never overwritten');
await db.exec('begin;alter function public.save_worker_personnel_profile(uuid,jsonb) set search_path=public;');
await assert.rejects(db.exec(sql.replace('begin;','')),/personnel_current_routine_drift/);checks++;await db.exec('rollback');
eq(await collect(),original,'changed writer dependency survives refusal until explicit rollback');
await assert.rejects(db.exec(sql.replace(/commit;\s*$/,()=>"do $$begin raise exception 'new_wrapper_late_failure';end$$;commit;")),/new_wrapper_late_failure/);checks++;await db.exec('rollback');
eq(await collect(),original,'late failure returns all four targets and metadata');
eq(await capsule(),baseline,'late failure preserves identities/company/provider/master/data');
// Prove the new data guard detects unauthorized row changes, without weakening
// the original P34 candidate. All changes are to this synthetic fixture only.
const afterMarker='do $rows_after$';
assert.equal(sql.split(afterMarker).length,2);
const injected=sql.replace(afterMarker,()=>"update public.worker_personnel_profiles set address='fixture forbidden row change';\n"+afterMarker);
await assert.rejects(db.exec(injected),/personnel_current_business_rows_changed/);checks++;await db.exec('rollback');
eq(await capsule(),baseline,'new row invariant rolls synthetic forbidden DML back');
await db.exec(sql);const applied=await collect(),after=await capsule();
eq(after.rows,baseline.rows,'source-only application preserves every business and identity row');eq(after.acl,baseline.acl,'original table and column ACL/RLS preserved');
for(const key of ['managerOff','managerOn','owner','admin','self','outsider','deleted']){
 await actor(actors[key]);
 const allowed=['managerOn','owner','admin','self'].includes(key);
 eq((await db.query('select count(*)::int n from worker_personnel_profiles where worker_id=$1',[W])).rows[0].n,allowed?1:0,key+' direct read');
 eq((await db.query('select private.can_edit_worker_personnel($1)as b',[W])).rows[0].b,allowed,key+' write authorization');
 if(['managerOn','owner','admin'].includes(key))eq(Array.isArray((await db.query('select public.employee_personnel_rows()as v')).rows[0].v),true,key+' legitimate legacy RPC');
 else{await assert.rejects(db.query('select public.employee_personnel_rows()'),e=>e.code==='42501');checks++;}
}
await db.exec('reset role');
const payload=(await db.query('select private.worker_personnel_payload($1)as v',[fresh])).rows[0].v;
await db.exec('begin');await actor(actors.managerOff);await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2::jsonb)',[fresh,JSON.stringify({...payload,address:'fixture denied'})]));checks++;await db.exec('rollback;reset role');
eq(await capsule(),after,'real save denial leaves complete applied snapshot unchanged');
for(const key of ['owner','admin']){await db.exec('begin');await actor(actors[key]);const saved=(await db.query('select public.save_worker_personnel_profile($1,$2::jsonb)as v',[fresh,JSON.stringify({...payload,address:'fixture legitimate'})])).rows[0].v;eq(saved.status,'saved',key+' actual save remains allowed');await db.exec('rollback;reset role');eq(await capsule(),after,key+' save rollback keeps identity/provider/company invariant');}
const emergency=await prepare(applied);
await db.exec('begin;alter function private.can_edit_worker_personnel(uuid) set search_path=public;');
await assert.rejects(db.exec(emergency.replace('begin;','')),/personnel_current_routine_drift/);checks++;await db.exec('rollback');
eq(await collect(),applied,'emergency restoration refuses changed post-source');
await db.exec(emergency);eq(await collect(),original,'explicit emergency restoration returns exact function OIDs/definitions/metadata and policy contract');eq(await capsule(),baseline,'emergency restoration leaves all business identities and grants unchanged');
await actor(actors.managerOff);eq((await db.query('select count(*)::int n from worker_personnel_profiles where worker_id=$1',[W])).rows[0].n,1,'emergency restoration REOPENS original bypass; not ordinary safe rollback');await db.exec('reset role');
await db.exec(sql);eq(await collect(),applied,'exact guarded reapplication after restoration');eq((await capsule()).rows,baseline.rows,'reapplication preserves original data');
console.log(JSON.stringify({pass:true,checks,native_pg17:true,unchanged_p34_composition:true,original_function_oids_restored:true,full_current_catalog_guard:true,business_identity_unchanged:true,emergency_restore_reopens_old_permission_gap:true,automatic_unused_restore_supported:false,production_changed:false}));
await db.close();
`;
try{
 const script=join(folder,'proof.mjs');await writeFile(script,source+tail);
 if(process.env.SKO_PERSONNEL_GUARD_EMIT_ONLY)await writeFile(process.env.SKO_PERSONNEL_GUARD_EMIT_ONLY,source+tail);
 else{
  const run=spawnSync(process.execPath,[script,...process.argv.slice(2)],{stdio:'inherit',env:{...process.env,SKO_PERSONNEL_GUARD_FOLDER:folder,SKO_PERSONNEL_GUARD_GENERATOR:join(here,'prepare_personnel.py')}});
  if(run.error)throw run.error;process.exitCode=run.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
