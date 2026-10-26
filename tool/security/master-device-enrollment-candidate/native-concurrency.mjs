// PostgreSQL fixture only: no real users, passwords, or device keys.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const require=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json');
const { Client }=require('pg');
const actor='00000000-0000-0000-0000-000000000001';
const jwt=JSON.stringify({role:'authenticated',session_id:'00000000-0000-0000-0000-000000000002',is_anonymous:false});
const hash=s=>createHash('sha256').update(s).digest('hex');
const clients=[new Client(),new Client()];
try {
  await Promise.all(clients.map(c=>c.connect()));
  for (const c of clients) {
    await c.query("select set_config('test.actor',$1,false),set_config('test.jwt',$2,false)",[actor,jwt]);
  }
  const seed=clients[0];
  await seed.query('delete from master_device_enrollment_candidate.intents');
  await seed.query('delete from private.master_devices');
  await seed.query(`insert into private.master_devices(master_user_id,device_key,device_name,device_type)
    values ($1,repeat('1',32),'Synthetic 1','iphone'),($1,repeat('2',32),'Synthetic 2','ipad')`,[actor]);
  const specs=[{key:'x'.repeat(32),token:'y'.repeat(32)},{key:'z'.repeat(32),token:'w'.repeat(32)}];
  for (const x of specs) {
    const r=await seed.query("select public.prepare_master_device_enrollment_candidate($1,'mac','synthetic-correct') r",[hash(x.key)]);
    x.id=r.rows[0].r.intent_id;
    const p=await seed.query("select public.approve_master_device_intent_candidate($1,$2,'trusted_device') ok",[x.id,hash(x.token)]);
    assert.equal(p.rows[0].ok,true);
  }
  const results=await Promise.all(clients.map(async (c,i)=>{
    try {
      await c.query('begin');
      await c.query("select public.complete_master_device_intent_candidate($1,$2,'Synthetic Mac',$3)",
        [specs[i].id,specs[i].key,specs[i].token]);
      await c.query('commit');
      return 'success';
    } catch (e) {
      await c.query('rollback');
      if (!String(e.message).includes('master_device_limit')) throw e;
      return 'limit';
    }
  }));
  assert.deepEqual(results.sort(),['limit','success']);
  const count=await seed.query('select count(*)::int n from private.master_devices where master_user_id=$1 and revoked_at is null',[actor]);
  assert.equal(count.rows[0].n,3);
  console.log('Concurrent fourth active device rejected; fixture only.');
} finally { await Promise.all(clients.map(c=>c.end())); }
