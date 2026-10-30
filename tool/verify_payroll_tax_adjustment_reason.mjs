// Disposable synthetic SQL fixture; exact captured saver/validator/session helper,
// synthetic authorization/refresh prerequisites, no hosted credentials or users.
import fs from 'node:fs';
import assert from 'node:assert/strict';
let db, nativePg, nativeUrl;
if (process.argv[3] === 'postgres') {
 const pg=(await import(process.argv[2])).default;
 const url=new URL(process.env.SKO_TAX_REASON_FIXTURE_URL ?? '');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_tax_reason_fixture') throw Error('disposable loopback fixture required');
 pg.types.setTypeParser(20,Number);
 const client=new pg.Client({connectionString:url.href});await client.connect();
 nativePg=pg;nativeUrl=url.href;
 db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql),close:()=>client.end()};
} else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',viewer='00000000-0000-0000-0000-000000000003';
const sid='70000000-0000-0000-0000-000000000001',sid2='70000000-0000-0000-0000-000000000002';
const month='2026-10-01';
async function actor(id=owner,session=sid,role='authenticated',extra={}) {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('fixture.blocked','',false)",[id,JSON.stringify({sub:id,role,session_id:session,...extra})]);
 await db.exec(`set role ${role}`);
}
const profile={insurance_mode:'rates',income_mode:'fixed',health:true,pension:false,employment:false,child_support:false,nursing:false,birth_date:null,health_base_yen:300000,pension_base_yen:0,dependents:0,non_taxable_yen:0,employment_excluded_yen:0,additional_social_deduction_yen:0,deduction_overrides:{}};
const save=async(version,value,reason='証明書と照合して訂正',scope=cid,worker=wid)=>(await db.query('select public.save_worker_payroll_tax_conditions_with_reason($1,$2,$3,$4,$5::jsonb,true,$6) value',[scope,worker,month,version,JSON.stringify(value),reason])).rows[0].value;
const oldSave=async(version,value)=>(await db.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,$4,$5::jsonb,true) value',[cid,wid,month,version,JSON.stringify(value)])).rows[0].value;
async function snapshot(){await db.exec('reset role');return (await db.query(`select jsonb_build_object(
 'conditions',(select coalesce(jsonb_agg(to_jsonb(t) order by version),'[]') from payroll_tax_private.worker_conditions t),
 'history',(select coalesce(jsonb_agg(to_jsonb(t) order by version),'[]') from payroll_tax_private.condition_history t),
 'reasons',(select coalesce(jsonb_agg(to_jsonb(t) order by version),'[]') from payroll_tax_private.adjustment_reasons t),
 'statements',(select coalesce(jsonb_agg(to_jsonb(t) order by period_start),'[]') from public.payroll_statements t)) value`)).rows[0].value;}
const funcs=['payroll_tax_private.read_conditions(uuid,uuid)','payroll_tax_private.save_conditions(uuid,uuid,date,bigint,jsonb,boolean)','payroll_tax_private.validate_conditions(jsonb)','public.save_worker_payroll_tax_conditions(uuid,uuid,date,bigint,jsonb,boolean)','private.require_reauthentication_session()'];
const metadata=async()=>(await db.query('select oid,prosrc,proowner,proacl,proconfig,prosecdef,provolatile from pg_proc where oid=any($1::regprocedure[]) order by oid',[funcs])).rows;
let groups=0;
try {
 await db.exec(read('tool/fixtures/payroll_tax_reason_foundation.sql'));
 await db.exec(read('tool/fixtures/payroll_tax_reason_dependencies.sql'));
 await db.exec(`revoke all on all functions in schema payroll_tax_private from public,anon,authenticated;
 grant execute on function payroll_tax_private.read_conditions(uuid,uuid),payroll_tax_private.save_conditions(uuid,uuid,date,bigint,jsonb,boolean) to authenticated;
 revoke all on function public.save_worker_payroll_tax_conditions(uuid,uuid,date,bigint,jsonb,boolean) from public,anon;
 grant execute on function public.save_worker_payroll_tax_conditions(uuid,uuid,date,bigint,jsonb,boolean) to service_role,authenticated;
 revoke all on function private.require_reauthentication_session() from public,anon,authenticated;`);
 const before=await metadata();
 const candidate=read('docs/candidates/payroll_tax_adjustment_reason.sql.review-only');
 const guard=candidate.match(/DO \$guard\$[\s\S]*?END \$guard\$;/)[0];
 await db.exec('begin;alter function private.require_reauthentication_session() security invoker');
 await assert.rejects(db.exec(guard),/dependency differs/);await db.exec('rollback');
 await db.exec("begin;create or replace function payroll_tax_private.read_conditions(cid uuid,wid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin return '{}'::jsonb;end$$");
 await assert.rejects(db.exec(guard),/dependency differs/);await db.exec('rollback');
 assert.deepEqual(await metadata(),before,'failed guards leave original dependencies unchanged');
 await db.exec(candidate);
 assert.deepEqual(await metadata(),before,'existing saver/validator/read/auth body, OID, owner, ACL and properties unchanged');
 const installed=await snapshot();assert.deepEqual(installed,{conditions:[],history:[],reasons:[],statements:[]});groups++;
 await db.query("insert into public.payroll_statements values($1,$2,$3,'finalized',true,'{\"original\":\"immutable\"}')",[cid,wid,month]);
 await actor();assert.equal((await db.query('select public.payroll_tax_adjustment_reason_contract_version() v')).rows[0].v,1);
 await oldSave(0,profile); // Ordinary profile/legacy clients remain compatible.
 let next={...profile,deduction_overrides:{health_insurance:12345}};
 let result=await save(1,next,'  通知書の金額へ訂正  ');
 assert.equal(result.adjustment_receipt.version,2);assert.equal(result.adjustment_receipt.reason,'通知書の金額へ訂正');assert.equal(result.adjustment_receipt.actor_id,owner);
 let saved=await snapshot();assert.equal(saved.reasons.length,1);assert.deepEqual(saved.reasons[0].before_value,profile);assert.deepEqual(saved.reasons[0].after_value,next);
 assert.deepEqual(saved.statements[0].detail,{original:'immutable'},'finalized statement left unchanged by the existing saver');
 await actor();assert.deepEqual((await save(1,next,'通知書の金額へ訂正')).adjustment_receipt,result.adjustment_receipt);assert.deepEqual(await snapshot(),saved,'same actor/SID/value/reason retry is no-op');groups++;
 for(const reason of ['',null,' \n\t　','x'.repeat(1001)]) {
  await actor();await assert.rejects(save(2,{...next,deduction_overrides:{health_insurance:12000}},reason));assert.deepEqual(await snapshot(),saved);
 }
 await actor();await assert.rejects(save(2,next),/変更がありません/);assert.deepEqual(await snapshot(),saved);
 await actor();await assert.rejects(save(1,next,'different reason'),/保存版/);assert.deepEqual(await snapshot(),saved);
 await actor(owner,sid2);await assert.rejects(save(1,next,'通知書の金額へ訂正'),/保存版/);assert.deepEqual(await snapshot(),saved);
 await actor();await assert.rejects(save(0,{...next,deduction_overrides:{health_insurance:12000}}),/更新されています/);assert.deepEqual(await snapshot(),saved);groups++;
 await actor();await assert.rejects(save(2,{...profile,deduction_overrides:{child_support:1}}),/手入力修正/);assert.deepEqual(await snapshot(),saved);
 for(const [id,session,role,extra] of [[viewer,'70000000-0000-0000-0000-000000000003','authenticated',{}],[owner,sid,'anon',{}],[owner,'70000000-0000-0000-0000-000000000099','authenticated',{}],[owner,sid,'authenticated',{is_anonymous:true}]]) {
  await actor(id,session,role,extra);await assert.rejects(save(2,profile));assert.deepEqual(await snapshot(),saved);
 }
 await actor();await assert.rejects(save(2,profile,'reason','10000000-0000-0000-0000-000000000002'));assert.deepEqual(await snapshot(),saved);
 await actor();await db.query("select set_config('fixture.blocked','1',false)");await assert.rejects(save(2,profile));assert.deepEqual(await snapshot(),saved);groups++;
 // Missing reasons cannot be backfilled onto an already committed legacy revision.
 await actor();await oldSave(2,{...next,deduction_overrides:{income_tax:500}});saved=await snapshot();
 await actor();await assert.rejects(save(2,{...next,deduction_overrides:{income_tax:500}}),/保存版/);assert.deepEqual(await snapshot(),saved);groups++;
 // An omitted existing reference is retained by the exact legacy saver and audited canonically.
 await db.exec('reset role');await db.query("update payroll_tax_private.worker_conditions set value=value||jsonb_build_object('insurance_basis_reference',jsonb_build_object('fixture',true)) where worker_id=$1",[wid]);
 await actor();result=await save(3,{...profile,deduction_overrides:{income_tax:600}},'基礎資料を保持して修正');
 saved=await snapshot();assert.deepEqual(saved.reasons.at(-1).after_value.insurance_basis_reference,{fixture:true});
 await actor();await save(3,{...profile,deduction_overrides:{income_tax:600}},'基礎資料を保持して修正');assert.deepEqual(await snapshot(),saved);groups++;
 // Reverting to automatic is an audited condition change, not a reason/table deletion.
 await actor();result=await save(4,profile,'自動計算に戻す');assert.equal(result.adjustment_receipt.version,5);
 saved=await snapshot();assert.deepEqual(saved.reasons.at(-1).after_value.deduction_overrides,{});assert.equal(saved.reasons.length,3);groups++;
 // A failed reason insertion must roll back the original saver/history in the same transaction.
 await db.exec(`create function public.fixture_reject_reason() returns trigger language plpgsql as $$begin raise exception 'fixture audit unavailable';end$$;
 create trigger fixture_reason_failure before insert on payroll_tax_private.adjustment_reasons for each row execute function public.fixture_reject_reason();`);
 await actor();await assert.rejects(save(5,next),/fixture audit unavailable/);assert.deepEqual(await snapshot(),saved);
 await db.exec('drop trigger fixture_reason_failure on payroll_tax_private.adjustment_reasons');groups++;
 await actor();await db.query("select set_config('fixture.rotate_session','1',false)");
 await assert.rejects(save(5,next),/session changed/);assert.deepEqual(await snapshot(),saved,'SID replacement after the old saver rolls back both records');
 await db.query("select set_config('fixture.rotate_session','',false)");groups++;
 await actor();await assert.rejects(db.query('select * from payroll_tax_private.adjustment_reasons'),/permission denied/);
 await assert.rejects(db.query('delete from payroll_tax_private.adjustment_reasons'),/permission denied/);
 const history=(await db.query('select public.read_worker_payroll_tax_adjustment_history($1,$2) value',[cid,wid])).rows[0].value;
 assert.equal(history.company_id,cid);assert.equal(history.worker_id,wid);assert.equal(history.items.length,3);assert.equal(history.items[0].reason,'自動計算に戻す');assert.equal(history.truncated,false);assert.equal('session_id' in history.items[0],false);
 await actor(viewer,'70000000-0000-0000-0000-000000000003');
 assert.equal((await db.query('select public.read_worker_payroll_tax_adjustment_history($1,$2) value',[cid,wid])).rows[0].value.items.length,3,'authorized viewer can read the same scoped history');
 await actor();await assert.rejects(db.query('select public.read_worker_payroll_tax_adjustment_history($1,$2)',[cid,'40000000-0000-0000-0000-000000000002']),/access denied/);groups++;
 await db.exec('reset role');await assert.rejects(db.exec("update payroll_tax_private.adjustment_reasons set reason='rewritten'"),/append-only/);
 await assert.rejects(db.exec('delete from payroll_tax_private.adjustment_reasons'),/append-only/);
 await db.exec(`reset role;insert into payroll_tax_private.adjustment_reasons(company_id,worker_id,starts_on,version,reason,actor_id,session_id,changed_at,after_value)
 select '${cid}','${wid}','${month}',n,'synthetic history','${owner}','${sid}',clock_timestamp(),'{}' from generate_series(100,201) n;`);
 await actor();const bounded=(await db.query('select public.read_worker_payroll_tax_adjustment_history($1,$2) value',[cid,wid])).rows[0].value;
 assert.equal(bounded.items.length,100);assert.equal(bounded.truncated,true);groups++;
 if(nativePg) {
  const first=new nativePg.Client({connectionString:nativeUrl}),second=new nativePg.Client({connectionString:nativeUrl});
  await first.connect();await second.connect();
  try {
   for(const client of [first,second]) {
    await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[owner,JSON.stringify({sub:owner,role:'authenticated',session_id:sid})]);
    await client.query('set role authenticated');
   }
   await first.query('begin');
   const winner={...profile,deduction_overrides:{income_tax:700}};
   await first.query('select public.save_worker_payroll_tax_conditions_with_reason($1,$2,$3,5,$4::jsonb,true,$5)',[cid,wid,month,JSON.stringify(winner),'concurrent winner']);
   await second.query("set lock_timeout='100ms'");
   await assert.rejects(second.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,5,$4::jsonb,true)',[cid,wid,month,JSON.stringify({...profile,deduction_overrides:{income_tax:800}})]),/lock timeout/);
   await first.query('commit');
   await assert.rejects(second.query('select public.save_worker_payroll_tax_conditions($1,$2,$3,5,$4::jsonb,true)',[cid,wid,month,JSON.stringify({...profile,deduction_overrides:{income_tax:800}})]),/更新されています/);
   const won=await snapshot();assert.equal(won.conditions[0].version,6);assert.equal(won.conditions[0].value.deduction_overrides.income_tax,700);
   assert.equal(won.reasons.find(row=>row.version===6).reason,'concurrent winner');groups++;
  } finally {await first.query('rollback').catch(()=>{});await first.end();await second.end();}
 }
 await db.exec('reset role');assert.deepEqual(await metadata(),before,'all original function metadata still unchanged after use');
 console.log(`PASS ${groups} SQL boundary groups: exact legacy compatibility, private reason persistence, canonical CAS/retry, SID/role/scope, atomic rollback, automatic revert, bounded history.`);
} finally {await db.close();}
