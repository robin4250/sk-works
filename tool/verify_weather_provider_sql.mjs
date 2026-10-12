import {readFile} from 'node:fs/promises';import assert from 'node:assert/strict';
const modulePath=process.env.SKO_PGLITE_MODULE;
if(!modulePath)throw Error('Set SKO_PGLITE_MODULE to the installed PGlite module');
const {PGlite}=await import(modulePath),db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;create function public.is_current_user_master_admin() returns boolean language sql stable as $$ select current_setting('test.master',true)='true' $$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');create schema private;create table private.master_feature_settings(feature_key text primary key,enabled boolean);insert into private.master_feature_settings values('traffic_train_transfer',false);`);
 const sql=await readFile(new URL('../supabase/migrations/20261012033455_add_weather_provider_settings.sql',import.meta.url),'utf8');await db.exec(sql);
 const get=async query=>(await db.query(query)).rows;
 await assert.rejects(get(`select public.current_weather_provider()`),/authentication required/);
 await db.exec(`set role authenticated;select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);select set_config('test.master','false',false);`);
 assert.equal((await get('select public.current_weather_provider() as provider'))[0].provider,'openweather');
 await assert.rejects(get("select public.set_weather_provider('weatherkit')"),/master administrator required/);
 await assert.rejects(get('select * from private.weather_provider_settings'),/permission denied/);
 await db.exec("select set_config('test.master','true',false)");
 assert.equal((await get("select public.set_weather_provider('weatherkit') as provider"))[0].provider,'weatherkit');
 await assert.rejects(get("select public.set_weather_provider('invalid')"),/invalid weather provider/);
 await assert.rejects(get('select public.set_weather_provider(null)'),/invalid weather provider/);
 await db.exec('reset role');
 assert.equal((await get("select provider from private.weather_provider_settings"))[0].provider,'weatherkit');
 assert.equal((await get("select enabled from private.master_feature_settings where feature_key='traffic_train_transfer'"))[0].enabled,false);
 await db.exec(sql); // replay preserves the previously selected provider
 assert.equal((await get("select provider from private.weather_provider_settings"))[0].provider,'weatherkit');
 const rls=(await get("select relrowsecurity from pg_class where oid='private.weather_provider_settings'::regclass"))[0];assert.equal(rls.relrowsecurity,true);
 await db.exec("set role anon;select set_config('request.jwt.claim.sub','',false)");
 await assert.rejects(get('select public.current_weather_provider()'),/permission denied/);
 await assert.rejects(get("select public.set_weather_provider('openweather')"),/permission denied/);
 console.log('Weather provider SQL: master-only switching, read-only authenticated, RLS, replay and unrelated traffic data PASS');
}finally{await db.close();}
