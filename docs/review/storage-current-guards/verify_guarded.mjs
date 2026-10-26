import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

// Reuse only the exact established synthetic bootstrap, not its successful tests.
const root=process.env.SKO_SECURITY_CHECKOUT_ROOT??process.cwd();
const here=dirname(fileURLToPath(import.meta.url));
const source=await readFile(join(root,'tool/security/storage_session_boundary_check.mjs'),'utf8');
if(createHash('sha256').update(source).digest('hex')!=='bed8dbf1e4cb6c2252c406b5d34f10880345c3d72b9982f4af20643d8f906b6c')throw Error('reviewed_bootstrap_drift');
const marker=' const before=await snapshot();';
if(source.split(marker).length!==2)throw Error('bootstrap_marker_drift');
const prefix=source.split(marker)[0].replace("const here=path.dirname(fileURLToPath(import.meta.url));",'const here='+JSON.stringify(join(root,'tool/security'))+';');
const folder=await mkdtemp(join(tmpdir(),'sko-storage-guard-fixture-'));
const tail=String.raw`
 const {writeFile,readFile}=await import('node:fs/promises');
 const {execFileSync}=await import('node:child_process');
 const folder=process.env.SKO_STORAGE_GUARD_TEST_FOLDER;
 const generator=process.env.SKO_STORAGE_GUARD_GENERATOR;
 const checkout=process.env.SKO_SECURITY_CHECKOUT_ROOT;
 await db.exec('create role service_role;create table auth.sessions(id uuid,user_id uuid,not_after timestamptz);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting(\'request.jwt.claims\',true),\'\'),\'{}\')::jsonb$$;');
 const policyQuery="select coalesce(jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'roles',to_jsonb(roles),'cmd',cmd,'qual',qual,'with_check',with_check,'permissive',permissive)order by policyname),'[]'::jsonb)as policies from pg_policies where schemaname='storage'and tablename='objects'";
 const policies=async()=>(await db.query(policyQuery)).rows;
 const beforePolicies=await policies();
 const originals=(await db.query("select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'security_definer',p.prosecdef,'volatility',p.provolatile)order by n.nspname,p.proname)as routines from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'and p.proname in('account_access_allowed','document_submission_access','has_company_feature','personnel_portrait_path','personnel_view_allowed','try_uuid')")).rows;
 const objectCatalog=(await db.query("select jsonb_build_object('relation',(select jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity)from pg_class c where c.oid='storage.objects'::regclass),'schema',(select jsonb_build_object('owner',pg_get_userbyid(nspowner),'acl',nspacl::text)from pg_namespace where nspname='storage'),'object_columns',(select jsonb_agg(jsonb_build_object('name',attname,'type',format_type(atttypid,atttypmod),'not_null',attnotnull)order by attnum)from pg_attribute where attrelid='storage.objects'::regclass and attnum>0 and not attisdropped))as catalog")).rows;
 await writeFile(folder+'/policies.json',JSON.stringify(beforePolicies));await writeFile(folder+'/routines.json',JSON.stringify(originals));await writeFile(folder+'/catalog.json',JSON.stringify(objectCatalog));
 async function generate(kind,post){
  const args=[generator,'--source-root',checkout,'--policies',folder+'/policies.json','--routines',folder+'/routines.json','--catalog',folder+'/catalog.json','--kind',kind,'--output',folder+'/candidate.sql'];
  if(post){await writeFile(folder+'/post.json',JSON.stringify(post));args.push('--post-policies',folder+'/post.json');}
  execFileSync('python3',args,{stdio:'pipe'});return await readFile(folder+'/candidate.sql','utf8');
 }
 const compare=(a,b,message)=>{assert.deepEqual(a,b,message);checks++;};
 const business=async()=>{const x=JSON.parse(await snapshot());delete x.acl;return x;};
 const originalBusiness=await business();
 const feature=await generate('feature');
 compare((feature.match(/^begin;$/gm)??[]).length,1,'feature single transaction');
 await db.exec('create policy unexpected_storage_policy on storage.objects for select to authenticated using(false)');
 await assert.rejects(db.exec(feature),/storage_review_policies_drift/);checks++;await db.exec('rollback;drop policy unexpected_storage_policy on storage.objects');
 compare(await policies(),beforePolicies,'unknown policy refusal leaves exact original catalog');
 await db.exec('alter table storage.objects add column unexpected_fixture_column text');
 await assert.rejects(db.exec(feature),/storage_review_columns_drift/);checks++;await db.exec('rollback;alter table storage.objects drop column unexpected_fixture_column');
 // Dropped columns are intentionally excluded by the same actual catalog query.
 await db.exec('begin;alter function private.account_access_allowed() set search_path=public;');
 await assert.rejects(db.exec(feature.replace('begin;','')),/storage_review_helper_drift/);checks++;await db.exec('rollback');
 await db.exec(feature);await visible(manager,0);await visible(own,1);await visible(admin,1);await visible(owner,1);await visible(other,0);await visible(null,0);
 compare(await business(),originalBusiness,'feature delta preserves original objects and identity/business rows');
 const featurePolicies=await policies();
 const restoreFeature=await generate('feature',featurePolicies);
 await db.exec(restoreFeature);compare(await policies(),beforePolicies,'manual feature restoration returns exact original policy catalog');await visible(manager,1);
 // Apply feature, then generate the live layer from its actual fresh post-catalog.
 await db.exec(feature);await writeFile(folder+'/policies.json',JSON.stringify(await policies()));
 const live=await generate('live');
 await assert.rejects(db.exec(live.replace('commit;',()=> 'do $$begin raise exception \'injected_late_failure\';end$$;commit;')),/injected_late_failure/);checks++;await db.exec('rollback');
 compare((await db.query("select to_regclass('private.storage_session_guard_rollout')is null as absent")).rows[0].absent,true,'failed installation removes all new live state');
 compare(await policies(),featurePolicies,'failed installation leaves policy catalog exact');
 await db.exec(live);const livePolicies=await policies();
 const restoreLive=await generate('live',livePolicies);
 compare((await db.query('select enabled from private.storage_session_guard_rollout')).rows[0].enabled,false,'live rollout installs OFF');
 compare((await db.query("select has_table_privilege('authenticated','private.storage_session_guard_installation','select')as readable")).rows[0].readable,false,'installation receipt is owner only');
 await db.exec('create view public.fixture_unknown_guard_dependency as select private.worker_storage_session_allowed()');
 await assert.rejects(db.exec(restoreLive),e=>e.code==='2BP01');checks++;await db.exec('rollback');
 compare(await policies(),livePolicies,'unknown external dependency refuses restoration atomically');
 await db.exec('drop view public.fixture_unknown_guard_dependency');
 await db.exec(restoreLive);compare(await policies(),featurePolicies,'unused live restoration returns exact policy catalog');
 compare((await db.query("select to_regclass('private.storage_session_guard_rollout')is null and to_regclass('private.storage_session_guard_installation')is null and to_regprocedure('private.worker_storage_session_allowed()')is null as absent")).rows[0].absent,true,'unused restoration removes only known new objects');
 await db.exec(live);compare(await business(),originalBusiness,'reinstallation leaves business data unchanged');
 await db.exec('update private.storage_session_guard_rollout set enabled=true');
 await assert.rejects(db.exec(restoreLive),/storage_live_restore_requires_off/);checks++;await db.exec('rollback');
 await db.exec('update private.storage_session_guard_rollout set enabled=false');
 await assert.rejects(db.exec(restoreLive),/storage_live_restore_requires_unused/);checks++;await db.exec('rollback');
 compare(await policies(),livePolicies,'ON then OFF cannot masquerade as unused removal');
 compare(await business(),originalBusiness,'used restore refusal preserves all original data');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,new_wrapper_only:true,reuses_original_role_bootstrap:true,live_gate_default_off:true,unused_restore_and_reinstall:true,unknown_dependency_refused:true,on_then_off_removal_refused:true,actual_hosted_storage_or_oauth:false,production_changed:false}));
}catch(e){console.error(e.code??'',e.message);process.exitCode=1;}finally{await db.close();}
`;
try{
 const script=join(folder,'proof.mjs');await writeFile(script,prefix+tail);
 if(process.env.SKO_STORAGE_GUARD_EMIT_ONLY){await writeFile(process.env.SKO_STORAGE_GUARD_EMIT_ONLY,prefix+tail);}
 else{
  const run=spawnSync(process.execPath,[script,...process.argv.slice(2)],{stdio:'inherit',env:{...process.env,SKO_SECURITY_CHECKOUT_ROOT:root,SKO_STORAGE_GUARD_TEST_FOLDER:folder,SKO_STORAGE_GUARD_GENERATOR:join(here,'prepare_storage_guards.py')}});
  if(run.error)throw run.error;process.exitCode=run.status??1;
 }
}finally{await rm(folder,{recursive:true,force:true});}
