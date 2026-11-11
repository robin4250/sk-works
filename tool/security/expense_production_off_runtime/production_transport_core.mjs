// Dedicated direct PostgreSQL transport. No pool, URL, retry or TLS downgrade.
import {createHash} from 'node:crypto';
import {checkServerIdentity} from 'node:tls';
export const PROJECT='ztktgquxvcxcjxtluspu';
export const HOST=`db.${PROJECT}.supabase.co`;
const digest=b=>createHash('sha256').update(b).digest('hex');
export function connectionOptions(password) {
 if(typeof password!=='string'||!password||Buffer.byteLength(password)>1024||/[\r\n\0]/.test(password)) throw Error('credential_refused');
 return {host:HOST,port:5432,database:'postgres',user:'postgres',password,
  ssl:{rejectUnauthorized:true,servername:HOST,minVersion:'TLSv1.2',
   checkServerIdentity:(_host,cert)=>checkServerIdentity(HOST,cert)},
  connectionTimeoutMillis:5000,query_timeout:35000,
  application_name:'sko-expense-default-off-once',keepAlive:false};
}
export async function executeRequest(request,Client) {
 if(!request||Object.keys(request).sort().join(',')!=='mode,password,sha256,sql'
  ||!['install','read-only'].includes(request.mode)||typeof request.sql!=='string'
  ||!request.sql||Buffer.byteLength(request.sql)>16777216
  ||!/^[a-f0-9]{64}$/.test(request.sha256)||digest(Buffer.from(request.sql))!==request.sha256) throw Error('request_refused');
 if(request.mode==='install'&&(!request.sql.startsWith('BEGIN')||!request.sql.includes('DO $expense_operator_preflight$')||!request.sql.trimEnd().endsWith('COMMIT;'))) throw Error('install_refused');
 if(request.mode==='read-only'&&!request.sql.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;')) throw Error('read_refused');
 const client=new Client(connectionOptions(request.password));
 client.on('error',()=>{});client.on('notice',()=>{});
 try {
  await client.connect();
  const stream=client.connection?.stream;
  if(stream?.encrypted!==true||stream.authorized!==true) throw Error('tls_refused');
  // No SET ROLE, inherited PGOPTIONS, pool/session reuse or caller SQL prefix.
  await client.query("set search_path=public;set statement_timeout='30s';set lock_timeout='3s';set idle_in_transaction_session_timeout='35s'");
  if(request.mode==='read-only') await client.query('set default_transaction_read_only=on');
  const identity=(await client.query("select current_database() db,session_user actor,current_user effective,current_setting('search_path') path,current_setting('default_transaction_read_only') readonly")).rows[0];
  if(identity?.db!=='postgres'||identity.actor!=='postgres'||identity.effective!=='postgres'||identity.path!=='public'
   ||(request.mode==='read-only'&&identity.readonly!=='on')) throw Error('session_refused');
  // Exactly one immutable payload submission. Never split/rebuild BEGIN/COMMIT.
  const response=await client.query(request.sql);
  if(request.mode==='install') return {acknowledged:true};
  const rows=(Array.isArray(response)?response:[response]).flatMap(r=>r.rows??[]);
  const captures=rows.filter(r=>Object.hasOwn(r,'jsonb_build_object'));
  if(captures.length!==1||captures[0].jsonb_build_object?.read_only!=='on') throw Error('observation_refused');
  if((await client.query('show transaction_read_only')).rows[0]?.transaction_read_only!=='on') throw Error('observation_refused');
  if(Buffer.byteLength(JSON.stringify(captures[0].jsonb_build_object))>16777216) throw Error('observation_refused');
  return captures[0].jsonb_build_object;
 } finally {try{await client.end();}catch{}}
}
