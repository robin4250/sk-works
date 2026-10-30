// Disposable CI database only. A marker established on an empty loopback
// database is required before the second phase can reset fixture-owned schemas.
import {createRequire} from 'node:module';
const require=createRequire(new URL('./security/fixture_dependencies/package.json',import.meta.url));
const {Client}=require('pg');
const uri=new URL(process.env.PARTNER_BANK_TEST_DATABASE_URL??'');
if(!['localhost','127.0.0.1'].includes(uri.hostname)||uri.pathname!='/partner_bank_fixture'||uri.username!=='postgres'||uri.password!=='fixture-only')throw Error('Dedicated disposable fixture URL required');
const action=process.argv[2];if(!['initialize','reset'].includes(action))throw Error('Explicit initialize/reset required');
const client=new Client({connectionString:uri.href});await client.connect();
try{
 if((await client.query('select current_database() name')).rows[0].name!=='partner_bank_fixture')throw Error('Wrong fixture database');
 if(action==='initialize'){
  const tables=(await client.query("select count(*)::int n from pg_tables where schemaname in ('public','private','auth','extensions')")).rows[0].n;
  const schemas=(await client.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','extensions')")).rows[0].n;
  if(tables!==0||schemas!==0)throw Error('Initialize requires an empty disposable database');
 }else{
  const marker=(await client.query('select value from public.sko_atomic_fixture_marker')).rows;
  if(marker.length!==1||marker[0].value!=='isolated-atomic-fixture-v1')throw Error('Owned fixture marker missing');
  await client.query('begin;drop schema private cascade;drop schema auth cascade;drop schema extensions cascade;drop schema public cascade;drop role anon;drop role authenticated;drop role service_role;create schema public;commit');
 }
 await client.query("create table public.sko_atomic_fixture_marker(value text not null);insert into public.sko_atomic_fixture_marker values('isolated-atomic-fixture-v1')");
 console.log(JSON.stringify({action,disposable:true,production:false}));
}finally{await client.end();}
