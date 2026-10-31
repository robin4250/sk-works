// Source-only verification. Auth rows and claims are synthetic, never GoTrue.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import pg from '../security/fixture_dependencies/node_modules/pg/lib/index.js';
const raw=process.env.SKO_TRADE_FIXTURE_URL;
const url=new URL(raw);
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_trade_fixture'||url.username!=='postgres'||url.password!=='fixture-only'||url.search||url.hash)throw Error('Disposable loopback fixture only');
const a=new pg.Client({connectionString:raw});const b=new pg.Client({connectionString:raw});
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,other,owner,manager,employee,another,foreign,worker,worker2,requirement,sid]=Array.from({length:11},(_,i)=>id(i+1));
let waits=0,checks=0;
const check=(actual,expected)=>{assert.deepEqual(actual,expected);checks++;};
const read=readFileSync(new URL('./read-catalog.sql',import.meta.url),'utf8');
const snapshot=async()=>(await a.query(read)).rows[0].snapshot;
function capsule(snapshot,target,approved=true){
 const script=`import json,sys\nfrom prepare_activation import build\nprint(build(json.loads(sys.stdin.read()),${target?'True':'False'},${approved?'True':'False'}))`;
 const r=spawnSync('python3',['-c',script],{cwd:new URL('.',import.meta.url),input:JSON.stringify(snapshot),encoding:'utf8'});
 if(r.status!==0)throw Error(r.stderr);return r.stdout;
}
async function denied(sql){await assert.rejects(a.query(sql));await a.query('rollback');checks++;}
async function observeWait(pid){
 const deadline=Date.now()+5000;
 while(Date.now()<deadline){
  const r=(await a.query(`select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1`,[pid])).rows[0];
  if(r?.wait_event_type==='Lock'&&r.blockers.includes(a.processID)){waits++;return;}
  await new Promise(resolve=>setTimeout(resolve,20));
 }
 throw Error('Expected actual second-connection lock wait was not observed');
}
try{
 await a.connect();await b.connect();
 const version=Number((await a.query("select current_setting('server_version_num') v")).rows[0].v);
 assert.ok(version>=170000&&version<180000);
 check((await a.query("select count(*)::int n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n,0);
 // Reuse the existing verifier's two literal synthetic schema/session SQL
 // blocks; never eval JS and reject interpolation. The exemption candidate
 // itself is executed verbatim below.
 const fixture=readFileSync(new URL('../verify_worker_document_exemption.mjs',import.meta.url),'utf8');
 const blocks=[...fixture.matchAll(/await db\.exec\(`([\s\S]*?)`\);/g)].slice(0,2).map(x=>x[1]);
 check(blocks.length,2);
 for(const block of blocks){assert.ok(!block.includes('${'));await a.query(block);}
 let attention=readFileSync(new URL('../../supabase/migrations/20260922010000_add_required_document_attention.sql',import.meta.url),'utf8');
 attention=attention.replace("or wds.status in ('not_submitted','missing','expired')",`or wds.status in ('not_submitted','missing','expired')
      or (dr.name <> '銀行口座情報' and nullif(wds.attachment_path, '') is null)
      or (dr.name = '銀行口座情報' and not exists (
        select 1 from public.worker_private_bank_accounts ba where ba.worker_id = v_worker_id and ba.company_id = v_company_id))`);
 await a.query(attention);
 await a.query(readFileSync(new URL('../../docs/candidates/worker_document_exemption_20261027/install.sql.review-only',import.meta.url),'utf8'));
 await a.query("insert into public.company_members values($1,$2,'owner')",[company,owner]);
 await a.query("insert into public.workers values($1,$2,$3,'active')",[worker,company,employee]);
 await a.query("insert into public.document_requirements values($1,$2,'本人書類',true,true,1)",[requirement,company]);
 await a.query('insert into auth.users(id) values($1)',[owner]);
 await a.query('insert into auth.sessions values($1,$2,null)',[sid,owner]);
 await b.query("select set_config('test.uid',$1,false),set_config('test.sid',$2,false)",[owner,sid]);
 await b.query('set role authenticated');
 const call=(version,active)=>b.query('select public.worker_document_exemption($1,$2::jsonb) result',['set',JSON.stringify({company_id:company,worker_id:worker,requirement_id:requirement,active,expected_version:version,reason:'Synthetic guard boundary fixture'})]);
 await assert.rejects(call(0,true),e=>e.code==='42501');checks++;
 let before=await snapshot();await denied(capsule(before,true,false));check((await snapshot()).module_state,before.module_state);
 await a.query(capsule(before,true));check((await snapshot()).module_state.enabled,true);
 await a.query(capsule(await snapshot(),false));check((await snapshot()).module_state.enabled,false);
 before=await snapshot();
 // Hold the exact activation TX before COMMIT, then start the real candidate
 // RPC. Inspect pg_stat_activity instead of inferring a wait from a delay.
 await a.query(capsule(before,true).replace(/commit;\s*$/i,''));
 let settled=false;
 const pending=call(0,true).then(r=>{settled=true;return r;},e=>{settled=true;throw e;});
 await observeWait(b.processID);check(settled,false);
 await a.query('commit');check((await pending).rows[0].result.item.version,1);
 check((await snapshot()).module_state,{settings_count:1,enabled:true,decision_count:1,event_count:1});
 const rowsBefore=(await a.query("select jsonb_build_object('decisions',(select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from private.worker_document_exemptions t),'events',(select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from private.worker_document_exemption_events t)) value")).rows[0].value;
 // Fixture-only pause DML checks the existing RPC's OFF boundary after use.
 // This is not a generated or approved after-use production capsule.
 await a.query('begin; lock table private.worker_document_exemption_settings in access exclusive mode;update private.worker_document_exemption_settings set enabled=false where singleton and enabled');
 settled=false;
 const stopped=call(1,false).then(r=>{settled=true;return {result:r};},error=>{settled=true;return {error};});
 await observeWait(b.processID);check(settled,false);await a.query('commit');
 check((await stopped).error?.code,'42501');
 const rowsAfter=(await a.query("select jsonb_build_object('decisions',(select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from private.worker_document_exemptions t),'events',(select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from private.worker_document_exemption_events t)) value")).rows[0].value;
 check(rowsAfter,rowsBefore);
 const listed=(await b.query('select public.worker_document_exemption($1,$2::jsonb) result',['list',JSON.stringify({company_id:company})])).rows[0].result;
 check(listed.can_manage,false);check(listed.items[0].active,true);
 console.log(JSON.stringify({checks,observed_lock_waits:waits,postgres:version,actual_candidate_rpc:true,synthetic_auth:true,real_gotrue:false,production:false}));
}finally{await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await Promise.allSettled([a.end(),b.end()]);}
