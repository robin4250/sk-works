// Appended after immutable setup only; none of the old 34/30 suites execute.
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
const pg=(await import(pathToFileURL(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js')).href)).default;
const observer=new pg.Client({connectionString:process.env.SKO_PERSONNEL_FIXTURE_URL});await observer.connect();
await observer.query("set statement_timeout='3s'");
const dir=path.join(root,'docs/candidates/personnel_birthday_atomic_20261030');
const install=fs.readFileSync(path.join(dir,'install.sql.review-only'),'utf8');
const restore=fs.readFileSync(path.join(dir,'restore-unused.sql.review-only'),'utf8');
let checks=0,stage='seed-pending';const equal=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
const signatures=['private.worker_personnel_payload(uuid)','private.apply_worker_personnel_payload(uuid,jsonb,uuid)','private.employee_personnel_view(uuid)','public.save_worker_personnel_profile(uuid,jsonb)'];
const catalogs=async client=>(await client.query(`select p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig,p.prosecdef,p.provolatile,p.proisstrict,p.proleakproof,p.proparallel,p.prokind,p.proretset,p.prorettype::regtype::text return_type from pg_proc p where p.oid=any($1::regprocedure[]) order by 1`,[signatures])).rows;
const column=async client=>(await client.query("select a.attname,format_type(a.atttypid,a.atttypmod) type,a.attnotnull from pg_attribute a where a.attrelid='public.worker_personnel_profiles'::regclass and a.attname='birth_date' and not a.attisdropped")).rows;
const snapshot=async()=>({base:await capsule(),functions:await catalogs(db),column:await column(db)});
const marker='-- birthday-atomic:after-step-1';
const finalMarker='-- birthday-atomic:before-final-guard';
function inject(sql,at,statement){assert.equal(sql.split(at).length,2);return sql.replace(at,()=>at+'\n'+statement);}
const failure="do $$begin raise sqlstate 'P0001' using message='synthetic_birthday_atomic_failure';end $$;";
const wrongBody="create or replace function private.worker_personnel_payload(p_worker_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select '{}'::jsonb$$;";
try{
 const old=(await db.query('select private.worker_personnel_payload($1) value',[W])).rows[0].value;
 await actor(actors.self);
 equal((await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) value',[W,JSON.stringify({...old,address:'SYNTHETIC PREEXISTING PENDING'})])).rows[0].value.status,'pending','synthetic pending seed');
 await db.exec('reset role');
 const before=await snapshot();equal(before.column,[],'original column absent');
 stage='install-intermediate-isolation';
 const split=install.indexOf(marker);assert.ok(split>0);
 await db.exec(install.slice(0,split));
 equal(await catalogs(observer),before.functions,'other connection sees all four old definitions until commit');
 equal(await column(observer),[],'other connection sees no newly added column until commit');
 await assert.rejects(db.exec(failure+install.slice(split)),error=>error.code==='P0001');checks++;
 await db.exec('rollback');equal(await snapshot(),before,'intermediate failure rolls back helpers/save/column/rows');
 stage='install-final-guard-failure';
 await assert.rejects(db.exec(inject(install,finalMarker,wrongBody)),error=>error.code==='55000'&&error.message==='personnel_birthday_atomic_final_catalog_drift');checks++;
 await db.exec('rollback');equal(await snapshot(),before,'final guard failure publishes no partial helper/save/column');
 stage='install-success';await db.exec(install);
 const installed=await snapshot();equal(installed.column,[{attname:'birth_date',type:'date',attnotnull:false}],'nullable date published');
 equal(installed.base.policies,before.base.policies,'original RLS unchanged');
 const changed=new Set(['worker_personnel_payload','apply_worker_personnel_payload','employee_personnel_view','save_worker_personnel_profile']);
 equal(installed.base.functions.filter(x=>!changed.has(x.proname)),before.base.functions.filter(x=>!changed.has(x.proname)),'all unrelated function definitions/metadata unchanged');
 equal(installed.base.acl.filter(x=>!(x.relname==='worker_personnel_profiles'&&x.attname==='birth_date')),before.base.acl,'existing table/column grants unchanged');
 for(const table of [...businessTables,...protectedTables]){
  const rows=installed.base.rows[table].map(row=>{const value={...row};if(table==='worker_personnel_profiles')delete value.birth_date;return value;});
  equal(rows,before.base.rows[table],'original rows and pending evidence '+table);
 }
 const metadata=rows=>rows.map(({definition,...rest})=>rest);
 equal(metadata(installed.functions),metadata(before.functions),'all four original attributes preserved');
 equal((await db.query('select private.worker_personnel_payload($1) value',[W])).rows[0].value.birth_date_contract_version,1,'both contract and comparison helper publish together');
 // Synthetic preservation setup, not proof that restore has a zero-use gate.
 await db.query("update public.worker_personnel_profiles set birth_date='1980-02-29' where worker_id=$1",[W]);
 const populated=await snapshot();
 stage='restore-intermediate-isolation';
 const restoreSplit=restore.indexOf(marker);assert.ok(restoreSplit>0);
 await db.exec(restore.slice(0,restoreSplit));
 equal(await catalogs(observer),populated.functions,'other connection still sees all four installed definitions during reverse restore');
 await assert.rejects(db.exec(failure+restore.slice(restoreSplit)),error=>error.code==='P0001');checks++;
 await db.exec('rollback');equal(await snapshot(),populated,'reverse restore middle failure retains all installed functions/date/pending');
 stage='restore-final-guard-failure';
 await assert.rejects(db.exec(inject(restore,finalMarker,wrongBody)),error=>error.code==='55000'&&error.message==='personnel_birthday_atomic_final_catalog_drift');checks++;
 await db.exec('rollback');equal(await snapshot(),populated,'reverse restore final guard failure leaves no partial withdrawal');
 stage='restore-success';await db.exec(restore);
 const restored=await snapshot();
 equal(restored.functions,before.functions,'exact four original definitions/attributes restored');
 equal(restored.base.rows,populated.base.rows,'dates/pending/approvals/identities/original rows retained');
 equal(restored.base.policies,populated.base.policies,'restore keeps original RLS');
 equal(restored.base.acl,populated.base.acl,'restore keeps columns/grants');
 equal(restored.column,populated.column,'restore retains new column/data');
 stage='retained-column-reinstall-refusal';
 await assert.rejects(db.exec(install),error=>error.code==='42701');checks++;
 await db.exec('rollback');equal(await snapshot(),restored,'retained date is not dropped to force reinstall');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,synthetic_claims_not_gotrue:true,old_suites_repeated:false,install_and_reverse_restore_atomic:true,independent_observer_no_partial_publish:true,intermediate_and_final_guard_failures_rollback:true,original_rows_pending_and_populated_date_retained:true,zero_use_gate_implemented:false,production_changed:false}));
}catch(error){console.error(JSON.stringify({stage,sqlstate:error.code??null,position:error.position??null}));throw error;}finally{await db.exec('rollback;reset role').catch(()=>{});await observer.end();await db.close();}
