import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import {info,root,validateEnvironment,prepare,snapshot,repair,sql} from './fixture.mjs';

if(process.argv.includes('--environment-faults')){
 const safe={PGHOST:'127.0.0.1',PGPORT:'55442',PGUSER:'postgres',PGDATABASE:'retirement_fixture',SKO_QUALIFICATION_FIXTURE_SERVER_ADDR:'127.0.0.1'};
 validateEnvironment(safe);let count=0;
 for(const v of [{PGHOST:'db.invalid'},{PGHOST:'127.0.0.1,remote'},{PGPORT:'5432'},{PGUSER:'service_role'},{PGDATABASE:'postgres'},{SKO_QUALIFICATION_FIXTURE_SERVER_ADDR:'203.0.113.1'},...['DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY','PGSERVICE','PGSERVICEFILE','PGHOSTADDR','PGOPTIONS'].map(k=>({[k]:'refuse'}))]){assert.throws(()=>validateEnvironment({...safe,...v}));count++;}
 console.log(`environment ${count} refusals; no connection`);process.exit(0);
}
const {sources,original}=prepare();
const part=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
const token=part({alg:'HS256'})+'.'+part({sub:info.actor,session_id:'60000000-0000-0000-0000-000000000001',exp:Math.floor(Date.now()/1000)+3600})+'.synthetic';
const trace=[];let phase='old';
const columns={company_members:['company_id','role','user_id'],workers:['id','company_id','user_id','name','affiliation','status'],qualification_master:['id','company_id','name','category','issuer','expiry_required','notes','is_active','source_name','source_reference','source_updated_at','external_source_id','is_company_custom'],worker_qualifications:['id','company_id','worker_id','qualification_master_id','certificate_number','issued_at','expires_at','issuer','attachment_path','attachment_back_path','attachment_extra_paths','notes','created_at','updated_at']};
function runAsActor(query){
 return JSON.parse(sql(`begin;set local statement_timeout='5s';set local lock_timeout='1s';set local role authenticated;set local "request.jwt.claim.sub"='${info.actor}';do $fixture$ begin if current_user <> 'authenticated' or auth.uid() is distinct from '${info.actor}'::uuid then raise exception 'fixture actor mismatch';end if;end $fixture$;${query};commit;`));
}
function reply(res,status,value){res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));}
function uuidLiteral(value){assert.match(value,/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i);return "'"+value+"'::uuid";}
async function body(req){let b='';for await(const c of req){b+=c;assert.ok(Buffer.byteLength(b)<1024);}const value=JSON.parse(b||'{}');assert.ok(value===null||(!Array.isArray(value)&&typeof value==='object'));return value;}
const server=http.createServer(async(req,res)=>{
 try{
  assert.equal(req.socket.remoteAddress,'127.0.0.1');
  assert.equal(req.headers.apikey,'fixture-only');assert.equal(req.headers.authorization,'Bearer '+token);
  const url=new URL(req.url,'http://127.0.0.1:55443');
  if(req.method==='GET'&&url.pathname==='/fixture-info')return reply(res,200,{...info,phase,original,current:snapshot(),trace,synthetic_auth:true,custom_http_bridge:true,real_storage_bytes:false,production_catalog:false});
  if(req.method==='POST'&&url.pathname==='/fixture-repair'){
   assert.equal(phase,'old');assert.deepEqual(await body(req),{});repair(sources);phase='repaired';return reply(res,200,{phase});
  }
  const rpc=/^\/rest\/v1\/rpc\/(ensure_current_user_worker|current_feature_permissions)$/.exec(url.pathname);
  if(req.method==='POST'&&rpc){
   assert.deepEqual((await body(req))??{},{});assert.equal([...url.searchParams].length,0);
   const result=runAsActor(`select to_json(public.${rpc[1]}())`);
   trace.push({phase,kind:'rpc',name:rpc[1]});return reply(res,200,result);
  }
  const table=/^\/rest\/v1\/([a-z_]+)$/.exec(url.pathname)?.[1];
  if(req.method!=='GET'||!Object.hasOwn(columns,table??''))return reply(res,404,{code:'FIXTURE_ROUTE',message:'route unavailable'});
  const selected=(url.searchParams.get('select')??'').split(',').map(x=>x.trim());assert.ok(selected.length&&selected.every(x=>columns[table].includes(x)));
  const where=[];let order='',limit='';
  for(const [key,value]of url.searchParams){
   if(key==='select')continue;
   if(key==='order'){
    const m=/^(name|created_at)\.(asc|desc)(?:\.(nullsfirst|nullslast))?$/.exec(value);assert.ok(m);assert.ok(columns[table].includes(m[1]));order=` order by ${m[1]} ${m[2]}`;continue;
   }
   if(key==='limit'){assert.ok(['1','2'].includes(value));limit=' limit '+value;continue;}
   if(key==='status'){assert.equal(table,'workers');assert.equal(value,'in.("active","inactive")');where.push("status in ('active','inactive')");continue;}
   assert.ok(['id','company_id','user_id','worker_id'].includes(key)&&columns[table].includes(key));assert.ok(value.startsWith('eq.'));
   where.push(key+'='+uuidLiteral(value.slice(3)));
  }
  const query=`select coalesce(json_agg(t),'[]'::json) from (select ${selected.join(',')} from public.${table}${where.length?' where '+where.join(' and '):''}${order}${limit})t`;
  const rows=runAsActor(query);assert.ok(Array.isArray(rows));
  trace.push({phase,kind:'read',table,selected,filters:Object.fromEntries(url.searchParams),rows:rows.length});
  if((req.headers.accept??'').includes('application/vnd.pgrst.object+json')){
   if(rows.length!==1)return reply(res,406,{code:'PGRST116',message:'exactly one row required'});
   return reply(res,200,rows[0]);
  }
  return reply(res,200,rows);
 }catch(error){console.error('FIXTURE_ERROR',req.url,error.message);reply(res,400,{code:'FIXTURE_INVALID',message:'isolated fixture request refused'});}
});
server.requestTimeout=10000;server.headersTimeout=5000;server.timeout=15000;server.keepAliveTimeout=1000;
server.listen(55443,'127.0.0.1',()=>{
 fs.writeFileSync(new URL('build/retired-qualification-context.json',root),JSON.stringify({url:'http://127.0.0.1:55443',apikey:'fixture-only',token,...info}),{mode:0o600});
 console.log('QUALIFICATION_BRIDGE_READY synthetic Auth; exact selected source SQL; deployable:false');
});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
