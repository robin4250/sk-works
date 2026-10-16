import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash,createHmac} from 'node:crypto';
const pg=(await import(process.argv[2]??'pg')).default;
const mode=process.argv[3],file=process.env.SKO_MASTER_CREDENTIAL_HTTP_FIXTURE;
const dbUrl=new URL(process.env.SKO_MASTER_PASSWORD_FIXTURE_URL??'');
const rest=new URL(process.env.SKO_MASTER_PASSWORD_POSTGREST_URL??'');
if(!['seed','verify'].includes(mode)||!file||dbUrl.protocol!=='postgres:'||dbUrl.hostname!=='127.0.0.1'||dbUrl.pathname!='/sko_master_password_fixture'||rest.protocol!=='http:'||rest.hostname!=='127.0.0.1')throw Error('Disposable client fixture only');
const actor='50000000-0000-4000-8000-000000000001',sid='50000000-0000-4000-8000-000000000002',company='50000000-0000-4000-8000-000000000003',device='50000000-0000-4000-8000-000000000004';
const deviceKey='fixture-real-http-master-client-device-key'.padEnd(64,'d');
const common='fixture-client-common-secondary-password',finalPassword='fixture-client-new-master-password';
const hash=s=>createHash('sha256').update(s).digest('hex');
const db=new pg.Client({connectionString:dbUrl.href});await db.connect();
async function protectedDigest(){
 const row=(await db.query(`select jsonb_build_object(
 'user',(select to_jsonb(x) from auth.users x where id=$1),
 'session',(select to_jsonb(x) from auth.sessions x where id=$2),
 'master',(select to_jsonb(x) from private.master_admins x where user_id=$1),
 'device',(select to_jsonb(x) from private.master_devices x where id=$4),
 'company',(select to_jsonb(x) from public.companies x where id=$3),
 'member',(select to_jsonb(x) from public.company_members x where user_id=$1 and company_id=$3),
 'secondary_hash',(select password_hash from public.user_secondary_credentials where user_id=$1)
 )::text value`,[actor,sid,company,device])).rows[0].value;
 return hash(row);
}
try {
 if(mode==='seed'){
  await db.query('begin');
  await db.query("insert into auth.users(id,provider) values($1,'google')",[actor]);
  await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);
  await db.query("insert into public.companies values($1,'independent synthetic SDK fixture')",[company]);
  await db.query("insert into public.company_members values($1,$2,'owner')",[company,actor]);
  await db.query('insert into private.master_admins values($1,true)',[actor]);
  await db.query('insert into private.master_devices(id,master_user_id,device_key) values($1,$2,$3)',[device,actor,deviceKey]);
  await db.query("insert into public.user_secondary_credentials(user_id,password_hash) values($1,extensions.crypt($2,extensions.gen_salt('bf',12)))",[actor,common]);
  await db.query('commit');
  const part=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const tokenBody=part({alg:'HS256',typ:'JWT'})+'.'+part({role:'authenticated',sub:actor,session_id:sid,is_anonymous:false,exp:Math.floor(Date.now()/1000)+3600});
  const token=tokenBody+'.'+createHmac('sha256','master-password-fixture-only-key-at-least-32-characters').update(tokenBody).digest('base64url');
  const session={access_token:token,refresh_token:'synthetic-unused-refresh',token_type:'bearer',expires_in:3600,
   user:{id:actor,aud:'authenticated',created_at:'2026-10-16T00:00:00Z',app_metadata:{providers:['google']},user_metadata:{}}};
  // Fixture-signed session only, written to runner temporary storage with no upload.
  await fs.writeFile(file,JSON.stringify({base_url:rest.href,actor,session_id:sid,device_key:deviceKey,session,protected_digest:await protectedDigest()}),{mode:0o600});
  console.log('PASS independent synthetic SDK seed prepared (no hosted user or secrets).');
 }else{
  const fixture=JSON.parse(await fs.readFile(file,'utf8'));assert.equal(fixture.actor,actor);
  assert.equal(await protectedDigest(),fixture.protected_digest,'SDK chain must preserve original user/provider/session/master/device/company/membership/secondary hash');
  const state=(await db.query('select version,password_hash from private.master_password_credentials where master_user_id=$1',[actor])).rows[0];
  assert.equal(state.version,'2');
  assert.equal((await db.query('select $1=extensions.crypt($2,$1) ok',[state.password_hash,finalPassword])).rows[0].ok,true);
  assert.equal((await db.query('select $1=extensions.crypt($2,$1) ok',[state.password_hash,common])).rows[0].ok,false);
  const results=(await db.query('select operation,result from private.master_password_requests where actor=$1 order by created_at',[actor])).rows;
  assert.deepEqual(results.map(r=>r.operation),['setup','change','unlock']);
  assert.deepEqual(results.map(r=>r.result.status),['applied','applied','verified']);
  console.log('PASS actual SDK RPC chain: independent hash/version/receipts and protected fixture state preserved.');
  console.log('LIMIT: real PostgreSQL/pgcrypto/PostgREST and product SDK repositories; session is fixture-signed, not real GoTrue/OAuth or Face ID.');
 }
}finally{await db.end();}
