import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
try {
 await db.exec(`create role authenticated;create role anon;create role service_role;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select auth.uid()='10000000-0000-0000-0000-000000000001'::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('test.denied',true),'')<>'1'$$;
 create table private.master_feature_settings(feature_key text primary key constraint master_feature_settings_feature_key_check check(feature_key in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')),enabled boolean not null default true,updated_at timestamptz,updated_by uuid);
 grant usage on schema public,auth to authenticated;grant execute on function auth.uid() to authenticated;
 `);
 await db.exec(read('supabase/migrations/20261012030758_traffic_master_feature_controls.sql'));
 const guard=read('supabase/migrations/20261011035332_guard_master_optional_feature_writes.sql');
 const from=guard.indexOf('create function private.require_master_optional_feature');
 const to=guard.indexOf('\n',guard.indexOf('revoke all on function private.require_master_optional_feature',from));
 await db.exec(guard.slice(from,to));
 await db.exec("insert into private.master_feature_settings values('vehicle_management',false,null,null),('route_assignment',true,null,null)");
 const before=(await db.query('select * from private.master_feature_settings order by feature_key')).rows;
 const meta=async()=>(await db.query("select oid,proowner,proacl,proconfig,prosecdef from pg_proc where oid=any(array['public.current_master_feature_flags()'::regprocedure,'public.set_master_feature_enabled(text,boolean)'::regprocedure,'private.require_master_optional_feature(text)'::regprocedure]) order by oid")).rows;
 const metadata=await meta();
 await db.exec(read(process.env.SKO_SEAL_MASTER_SQL || 'docs/candidates/company_seal_master_feature_20261020.sql.review-only'));
 assert.deepEqual(await meta(),metadata);
 assert.deepEqual((await db.query("select * from private.master_feature_settings where feature_key<>'company_seal_image_tools' order by feature_key")).rows,before);
 async function actor(id='10000000-0000-0000-0000-000000000001'){await db.exec('reset role');await db.query("select set_config('test.actor',$1,false)",[id]);await db.exec('set role authenticated');}
 await actor();let flags=(await db.query('select public.current_master_feature_flags() value')).rows[0].value;assert.equal(flags.company_seal_image_tools,true);assert.equal(flags.vehicle_management,false);assert.equal(flags.route_assignment,true);
 await db.query("select public.set_master_feature_enabled('company_seal_image_tools',false)");await db.exec('reset role');
 await assert.rejects(db.query("select private.require_master_optional_feature('company_seal_image_tools')"),/master feature disabled/);
 for(const key of [null,'unknown_feature'])await assert.rejects(db.query('select private.require_master_optional_feature($1)',[key]),/unsupported master feature/);
 await actor();await assert.rejects(db.query("select private.require_master_optional_feature('company_seal_image_tools')"),/permission denied/);
 await db.query("select public.set_master_feature_enabled('company_seal_image_tools',true)");await db.exec('reset role');await db.query("select private.require_master_optional_feature('company_seal_image_tools')");
 await actor('10000000-0000-0000-0000-000000000002');await assert.rejects(db.query("select public.set_master_feature_enabled('company_seal_image_tools',false)"),/master administrator/);
 await actor();await assert.rejects(db.query("select public.set_master_feature_enabled('unknown_feature',true)"),/unsupported master feature/);
 await db.exec('reset role');await assert.rejects(db.exec(read(process.env.SKO_SEAL_MASTER_SQL || 'docs/candidates/company_seal_master_feature_20261020.sql.review-only')),/allowlist differs|master optional guard differs/);await db.exec('rollback');
 console.log('PASS central seal gate: five defaults and metadata preserved, master toggle, read/execution OFF, unknown/null rejection, private ACL, repeat guard');
} catch(e){console.error(e.message);process.exitCode=1;} finally {await db.close();}
