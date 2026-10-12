// Disposable in-memory fixture; no production connection is accepted.
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(resolve(process.argv[2])).href);
const db=new PGlite();
const read=p=>readFileSync(resolve(root,p),'utf8');
const master='10000000-0000-0000-0000-000000000001';
const regular='10000000-0000-0000-0000-000000000002';
try {
 await db.exec(`create role anon;create role authenticated;create schema private;create schema auth;
 create table auth.users(id uuid primary key);insert into auth.users values('${master}'),('${regular}');
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
 create function public.is_current_user_master_admin() returns boolean language sql stable as $$select auth.uid()='${master}'::uuid$$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
 await db.exec(read('supabase/migrations/20260930065000_add_master_feature_controls.sql'));
 await db.exec(read('supabase/migrations/20260930065500_fix_master_feature_control_authorization.sql'));
 await db.exec(`update private.master_feature_settings set enabled=false,updated_by='${master}',updated_at='2026-10-01' where feature_key='vehicle_management'`);
 const rows=async()=> (await db.query('select * from private.master_feature_settings order by feature_key')).rows;
 const old=await rows();
 const guard=(await db.query("select prosrc from pg_proc where proname='is_current_user_master_admin'")).rows;
 const file=readdirSync(resolve(root,'supabase/migrations')).find(f=>f.endsWith('_traffic_master_feature_controls.sql'));
 await db.exec(read('supabase/migrations/'+file));
 assert.deepEqual((await rows()).filter(r=>!r.feature_key.startsWith('traffic_')),old);
 assert.deepEqual((await db.query("select prosrc from pg_proc where proname='is_current_user_master_admin'")).rows,guard);
 const flags=async()=> (await db.query('select current_master_feature_flags() value')).rows[0].value;
 await db.exec(`set role authenticated;set fixture.uid='${regular}'`);
 assert.deepEqual(await flags(),{vehicle_management:false,route_assignment:true,traffic_nearest_station:false,traffic_train_transfer:false,traffic_bus_stop:false});
 await assert.rejects(db.exec("select set_master_feature_enabled('traffic_nearest_station',true)"),/master administrator access required/);
 await assert.rejects(db.exec('select * from private.master_feature_settings'),/permission denied/);
 await db.exec(`set fixture.uid='${master}'`);
 for (const key of ['traffic_nearest_station','traffic_train_transfer','traffic_bus_stop']) {
  await db.exec(`select set_master_feature_enabled('${key}',true)`);
  assert.equal((await flags())[key],true);
  await db.exec(`select set_master_feature_enabled('${key}',false)`);
  assert.equal((await flags())[key],false);
 }
 await assert.rejects(db.exec("select set_master_feature_enabled('security',true)"),/unsupported master feature/);
 await assert.rejects(db.exec('select set_master_feature_enabled(null,true)'),/unsupported master feature/);
 await db.exec("set fixture.uid=''");
 assert.equal(await flags(),null);
 await assert.rejects(db.exec("select set_master_feature_enabled('traffic_bus_stop',true)"),/master administrator access required/);
 await db.exec('reset role;set role anon');
 await assert.rejects(db.exec('select current_master_feature_flags()'),/permission denied/);
 await assert.rejects(db.exec("select set_master_feature_enabled('traffic_bus_stop',true)"),/permission denied/);
 await db.exec('reset role');
 assert.deepEqual((await rows()).filter(r=>!r.feature_key.startsWith('traffic_')),old);
 const acl=(await db.query("select relrowsecurity,relacl from pg_class where oid='private.master_feature_settings'::regclass")).rows[0];
 assert.equal(acl.relrowsecurity,true);
 assert.ok(!JSON.stringify(acl.relacl).includes('authenticated'));
 console.log('PASS: three master traffic toggles, regular/anonymous denial, private table isolation, old flag rows and master guard preserved');
} finally {await db.close();}
