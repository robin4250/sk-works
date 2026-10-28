import {pathToFileURL} from 'node:url';
import path from 'node:path';
const pg=(await import(pathToFileURL(path.resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js')).href)).default;
const raw=process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL;
const u=new URL(raw||'http://invalid');
if(process.env.CI!=='true'||process.env.SKO_INVOICE_NOTICE_AUTH_HOOK!=='contract-v1'||u.protocol!=='postgresql:'||!['127.0.0.1','localhost'].includes(u.hostname)||u.port!=='53912'||u.pathname!=='/postgres'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('isolated GoTrue fixture only');
pg.types.setTypeParser(20,value=>{const n=Number(value);if(!Number.isSafeInteger(n))throw Error('unsafe bigint');return n;});
function wrap(c){
 const original=c.query.bind(c);
 c.query=async(q,a)=>{
  const value=await original(q,a);
  if(typeof q==='string'&&/(?:set\s+test\.uid|set_config\(\s*'test\.uid')/i.test(q))await original("select set_config('request.jwt.claim.sub',coalesce(current_setting('test.uid',true),''),false)");
  return value;
 };
 return c;
}
let fixture;
export class PGlite{
 constructor(){if(fixture)throw Error('one fixture only');fixture=this;this.client=wrap(new pg.Client({connectionString:raw}));this.ready=this.client.connect().then(async()=>{if((await this.client.query("select to_regclass('public.companies') x")).rows[0].x)throw Error('empty public fixture required');});}
 async query(q,a){await this.ready;try{return await this.client.query(q,a);}catch(e){console.error('fixture query:',q.slice(0,300));throw e;}}
 async exec(q){await this.ready;if(q.startsWith('create schema private;create schema auth;')){
  q=q.replace('create schema private;create schema auth;','create schema private;');
  q=q.replace("create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;",'');
  q=q.replace('create role anon;create role authenticated;','');
  q=q.replace('grant usage on schema public,private,auth to authenticated,anon;','grant usage on schema public,private to authenticated,anon;');
 }try{return await this.client.query(q);}catch(e){const n=Number(e.position||0);if(n)console.error('fixture SQL error near:',q.slice(Math.max(0,n-100),n+100));else console.error('fixture statement:',q.slice(0,300));throw e;}}
 async close(){await this.client.end();}
}
export async function connectFixture(){const c=wrap(new pg.Client({connectionString:raw}));await c.connect();return c;}
