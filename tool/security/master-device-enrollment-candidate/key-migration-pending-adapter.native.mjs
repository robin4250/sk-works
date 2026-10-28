// Native PostgreSQL fixture with synthetic auth rows. NOT a GoTrue/JWT test.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {generateKeyPairSync} from 'node:crypto';
import assert from 'node:assert/strict';
import {storePendingDeviceKey} from './key-migration-pending-adapter.mjs';
const require=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json');
const {Pool}=require('pg');
const pool=new Pool({max:3});
const actor='00000000-0000-0000-0000-000000000001';
const session='00000000-0000-0000-0000-000000000002';
const deviceId='00000000-0000-0000-0000-000000000003';
const pem=()=>generateKeyPairSync('ec',{namedCurve:'prime256v1'}).publicKey.export({type:'spki',format:'pem'}).toString();
// This wrapper sets SYNTHETIC fixture settings, never real JWT or caller input.
// A deployed adapter must obtain independently verified transaction context.
const fixturePool={connect:async()=>{
 const c=await pool.connect();
 await c.query("select set_config('test.actor',$1,false),set_config('test.jwt',$2,false)",
 [actor,JSON.stringify({role:'authenticated',session_id:session,is_anonymous:false})]);
 return c;
}};
const args={pool:fixturePool,actor,session,deviceId,publicKeyPem:pem()};
const count=async()=>Number((await pool.query('select count(*) from master_device_enrollment_candidate.pending_key_migrations')).rows[0].count);
try {
 for(const name of ['native-setup.sql','native-real-functions.sql','key-migration-registry.sql.review-only'])
  await pool.query(await readFile(new URL(name,import.meta.url),'utf8'));
 await pool.query(`insert into private.master_devices(id,master_user_id,device_key,device_name,device_type)
 values ($1,$2,'synthetic-identifier','Synthetic iPhone','iphone')`,[deviceId,actor]);
 const first=await storePendingDeviceKey(args);
 assert.equal(first.status,'pending');
 assert.deepEqual(await storePendingDeviceKey(args),first);
 assert.equal(await count(),1);
 await assert.rejects(storePendingDeviceKey({...args,session:'00000000-0000-0000-0000-000000000099',publicKeyPem:pem()}));
 assert.equal(await count(),1);
 await pool.query('update auth.sessions set not_after=clock_timestamp()-interval \'1 second\' where id=$1',[session]);
 await assert.rejects(storePendingDeviceKey({...args,publicKeyPem:pem()}));
 await pool.query('update auth.sessions set not_after=null where id=$1',[session]);
 await pool.query('update private.master_devices set is_locked=true where id=$1',[deviceId]);
 await assert.rejects(storePendingDeviceKey({...args,publicKeyPem:pem()}));
 assert.equal(await count(),1);
 await pool.query('update private.master_devices set is_locked=false where id=$1',[deviceId]);
 await assert.rejects(storePendingDeviceKey({...args,publicKeyPem:'invalid'}));
 assert.equal(await count(),1);
 // Client roles have neither schema access nor table rights; no activation API.
 for(const role of ['anon','authenticated']) {
  const c=await pool.connect();
  try {await c.query('begin');await c.query('set local role '+role);
   await assert.rejects(c.query('select * from master_device_enrollment_candidate.pending_key_migrations'),e=>e.code==='42501');
  }finally{await c.query('rollback');c.release();}
 }
 assert.equal((await pool.query('select device_key from private.master_devices where id=$1',[deviceId])).rows[0].device_key,'synthetic-identifier');
 console.log('Native pending adapter: idempotent save, foreign/expired session, locked device, malformed key, client ACL and unchanged legacy identifier passed. Synthetic auth only.');
}finally{await pool.end();}
