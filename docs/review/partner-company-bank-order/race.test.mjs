// Disposable PostgreSQL only. No production or real Auth credentials.
import assert from 'node:assert/strict';import {createRequire} from 'node:module';import {randomUUID} from 'node:crypto';
const require=createRequire(new URL('../../../tool/security/fixture_dependencies/package.json',import.meta.url));const {Client}=require('pg');
const uri=new URL(process.env.PARTNER_BANK_TEST_DATABASE_URL??'');if(!['localhost','127.0.0.1'].includes(uri.hostname)||uri.pathname!='/partner_bank_fixture')throw Error('Loopback fixture database required');
const clients=Array.from({length:3},()=>new Client({connectionString:uri.href}));const [control,revoker,writer]=clients;await Promise.all(clients.map(c=>c.connect()));
const id=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;const [company,actor,partner,sid]=[id(1),id(3),id(7),id(10)];
const bank={bank_name:'Fixture Bank',branch_name:'Fixture Branch',account_type:'普通',account_number:'0000123',account_holder:'FIXTURE SUPPLIER'};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function restore(){await control.query(`update public.company_members set role='admin' where company_id=$1 and user_id=$2;`,[company,actor]);await control.query("update public.partner_companies set status='active' where id=$1",[partner]);await control.query('update auth.users set banned_until=null,is_anonymous=false where id=$1',[actor]);await control.query('insert into auth.sessions(id,user_id,not_after) values($1,$2,null) on conflict(id) do update set user_id=excluded.user_id,not_after=null',[sid,actor]);}
async function identity(){await writer.query('set role authenticated');await writer.query("select set_config('test.uid',$1,false),set_config('request.jwt.claims',$2,false)",[actor,JSON.stringify({sub:actor,session_id:sid,role:'authenticated',is_anonymous:false})]);}
async function version(){return (await control.query('select max(version)::int n from private.partner_company_bank_versions')).rows[0].n??0;}
async function count(){return (await control.query('select count(*)::int n from private.partner_company_bank_versions')).rows[0].n;}
async function save(v){return writer.query('select public.save_partner_company_bank($1,$2,$3,$4,$5)',[company,partner,v,randomUUID(),bank]);}
async function locked(pid){for(let n=0;n<200;n++){const r=await control.query('select wait_event_type from pg_stat_activity where pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await wait(10);}throw Error('Expected actual row-lock wait was not observed');}
let checks=0;
try {
 const writerPid=(await writer.query('select pg_backend_pid() pid')).rows[0].pid,revokerPid=(await revoker.query('select pg_backend_pid() pid')).rows[0].pid;
 for(const scenario of ['role downgrade','partner stopped','session removed','session expired','user banned','actual anonymous']){
  await restore();await identity();const before=await count(),v=await version();await revoker.query('begin');
  if(scenario==='role downgrade')await revoker.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[company,actor]);
  if(scenario==='partner stopped')await revoker.query("update public.partner_companies set status='inactive' where id=$1",[partner]);
  if(scenario==='session removed')await revoker.query('delete from auth.sessions where id=$1',[sid]);
  if(scenario==='session expired')await revoker.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[sid]);
  if(scenario==='user banned')await revoker.query("update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=$1",[actor]);
  if(scenario==='actual anonymous')await revoker.query('update auth.users set is_anonymous=true where id=$1',[actor]);
  const pending=save(v).then(()=>({ok:true}),error=>({ok:false,code:error.code}));await locked(writerPid);await revoker.query('commit');
  const result=await pending;assert.deepEqual(result,{ok:false,code:'42501'},scenario);assert.equal(await count(),before,scenario);checks++;
 }
 await restore();await identity();const before=await count();await revoker.query('begin');await revoker.query('select pg_advisory_xact_lock(private.account_deletion_barrier_key($1))',[actor]);
 await assert.rejects(save(await version()),e=>e.code==='42501');assert.equal(await count(),before);await revoker.query('commit');checks++;
 // Conversely, a writer that already holds the reviewed SHARE locks must finish
 // before a revocation can commit. This is ordering, not cancellation of a begun TX.
 await restore();await identity();await writer.query('begin');await writer.query('select public.partner_company_bank_read($1,$2)',[company,partner]);
 const revocation=revoker.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[company,actor]);await locked(revokerPid);
 await save(await version());await writer.query('commit');await revocation;assert.equal(await count(),before+1);checks++;
 assert.equal((await control.query("select md5(prosrc) hash from pg_proc where oid='private.require_reauthentication_session()'::regprocedure")).rows[0].hash,'b5c8e2f259a99b3c69694ad0640080e5');checks++;
 console.log(JSON.stringify({result:'PASS native partner bank authorization races',checks,real_auth:false,production_changes:false,core_helper_unchanged:true}));
} finally {await Promise.allSettled([revoker.query('rollback'),writer.query('rollback')]);await Promise.all(clients.map(c=>c.end()));}
