// Runs the exact migration against isolated Postgres/PGlite, never a linked DB.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const otherCompany='20000000-0000-0000-0000-000000000001';
const owner='10000000-0000-0000-0000-000000000011';
const admin='10000000-0000-0000-0000-000000000012';
const worker='10000000-0000-0000-0000-000000000013';
const otherAdmin='20000000-0000-0000-0000-000000000012';
const item='employment_insurance';
const untouched='30000000-0000-0000-0000-000000000002';
const candidate='40000000-0000-0000-0000-000000000001';
const value={kind:'employment_insurance',label:'Fixture employment',total:777777,
 employee:123456,employer:654321,insurance_month:'2030-04-01',
 payroll_month:'2030-05-01',payment_month:'2030-06-01',
 source:{url:'https://example.test/fixture.pdf',publisher:'Fixture source only',
 document_hash:'fixture-hash',applicability:{business:'fixture'}}};
const nextValue={...value,total:888888,employee:234567};
async function actor(id,role='authenticated',allowed=true) {
 await db.exec('reset role');
 await db.query("select set_config('test.actor',$1,false),set_config('test.account_allowed',$2,false)",[id,String(allowed)]);
 await db.exec(`set role ${role}`);
}
async function save(version,payload=value,confirmed=true,targetCompany=company,targetItem=item) {
 return (await db.query('select public.save_manual_company_payroll_rate($1,$2,$3,$4::jsonb,$5) as result',
  [targetCompany,targetItem,version,JSON.stringify(payload),confirmed])).rows[0].result;
}
async function read(targetCompany=company) {
 return (await db.query('select public.read_company_payroll_rates($1) as result',[targetCompany])).rows[0].result;
}
const scope={insurer:'kyokai',prefecture:'東京都',employment_business:'construction'};
async function saveScope(version,payload=scope,confirmed=true,targetCompany=company) {
 return (await db.query('select public.save_company_payroll_rate_scope($1,$2,$3::jsonb,$4) as result',
 [targetCompany,version,JSON.stringify(payload),confirmed])).rows[0].result;
}
async function apply(version,confirmed=true,targetCandidate=candidate,targetCompany=company,targetItem=item) {
 return (await db.query('select public.apply_company_payroll_rate_candidate($1,$2,$3,$4,$5) as result',
 [targetCompany,targetItem,targetCandidate,version,confirmed])).rows[0].result;
}
try {
 await db.exec(fs.readFileSync('supabase/tests/company_payroll_rate_registry_bootstrap.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261009151946_company_payroll_rate_registry.sql','utf8'));
 // Check actual ACL and RLS, independent of application route reachability.
 const security=await db.query(`select c.relname,c.relrowsecurity,
  has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') as granted
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='payroll_rate_private' and c.relkind='r'`);
 assert.equal(security.rows.length,5);
 for(const row of security.rows) {assert.equal(row.relrowsecurity,true);assert.equal(row.granted,false);}
 for(const id of [worker,otherAdmin,'']) {
  await actor(id);
  await assert.rejects(read(),/admin access denied/);
  await assert.rejects(save(0),/admin access denied/);
  await assert.rejects(apply(0),/admin access denied/);
  await assert.rejects(saveScope(0),/admin access denied/);
 }
 await actor(admin,'authenticated',false);
 await assert.rejects(save(0),/admin access denied/);
 await assert.rejects(read(),/admin access denied/);
 await assert.rejects(saveScope(0),/admin access denied/);
 await actor(owner,'anon');
 await assert.rejects(read(),/permission denied/);
 await assert.rejects(save(0),/permission denied/);
 await assert.rejects(apply(0),/permission denied/);
 await assert.rejects(saveScope(0),/permission denied/);
 await actor(owner);
 await assert.rejects(db.query('select * from payroll_rate_private.settings'),/permission denied/);
 await assert.rejects(db.query('insert into payroll_rate_private.candidates(company_id) values($1)',[company]),/permission denied/);
 await assert.rejects(save(0,value,false),/confirmation required/);
 assert.equal((await read()).company_scope,null,'unconfigured scope must be null');
 const initial=await save(0);
 assert.equal(initial.version,1);assert.equal(initial.origin,'manual');
 assert.deepEqual(initial.value,value);
 await save(0,{...value,kind:'custom',label:'Untouched'},true,company,untouched);
 await actor(admin);
 await assert.rejects(read(otherCompany),/admin access denied/);
 await assert.rejects(save(1,value,true,otherCompany),/admin access denied/);
 const before=await read();
 for(const invalid of [
  {...value,kind:'income_tax'}, {...value,employee:0}, {...value,total:1.5},
  {...value,total:null}, {...value,insurance_month:'2030-13-01'},
  {...value,source:{...value.source,verified:true}}, {...value,unexpected:true},
  {...value,source:{...value.source,applicability:{}}},
  {...value,label:'x'.repeat(81)},
  {...value,source:{...value.source,publisher:'x'.repeat(201)}},
  {...value,source:{...value.source,document_hash:'x'.repeat(257)}},
  {...value,source:{...value.source,url:'https://example.test/'+'x'.repeat(2048)}},
  {...value,source:{...value.source,applicability:{business:12}}},
  {...value,source:{...value.source,applicability:{business:'x'.repeat(513)}}},
  {...value,source:{...value.source,applicability:Object.fromEntries(Array.from({length:21},(_,i)=>['k'+i,'v']))}},
  {...value,label:'x'.repeat(32769)},
 ]) await assert.rejects(save(1,invalid));
 await assert.rejects(save(0),/version conflict/);
 await assert.rejects(save(0,value,true,company,'30000000-0000-0000-0000-000000000003'),/standard kind ID/);
 await assert.rejects(save(0,{...value,kind:'custom',label:'  untouched  '},true,company,'30000000-0000-0000-0000-000000000003'),/duplicate key/);
 await assert.rejects(save(1,{...value,kind:'custom'}),/custom UUID/);
 await assert.rejects(save(1,value,null),/confirmation required/);
 assert.deepEqual(await read(),before,'rejected writes must preserve version and audit');
 const updated=await save(1,nextValue);
 assert.equal(updated.version,2);
 let state=await read();
 assert.equal(state.items.find(x=>x.item_id===untouched).version,1);
 const manualChange=state.history.find(x=>x.item_id===item && x.version===2);
 assert.equal(manualChange.actor_id,admin);assert.ok(manualChange.changed_at);
 assert.deepEqual(manualChange.before_value,value);assert.deepEqual(manualChange.after_value,nextValue);
 // Company applicability is a single source, distinct from rate source snapshots.
 await assert.rejects(saveScope(0,scope,false),/scope confirmation/);
 await assert.rejects(saveScope(0,scope,true,otherCompany),/admin access denied/);
 for(const invalid of [
  {...scope,insurer:'guessed'}, {...scope,prefecture:'address inferred'},
  {...scope,prefecture:12}, {...scope,employment_business:'guessed'},
  {...scope,address:'copy'}, {insurer:'kyokai',prefecture:'東京都'},
 ]) await assert.rejects(saveScope(0,invalid),/invalid/);
 const initialScope=await saveScope(0);
 assert.equal(initialScope.version,1);assert.deepEqual(initialScope.value,scope);
 assert.equal(initialScope.updated_by,admin);assert.ok(initialScope.updated_at);
 let scopedState=await read();
 assert.equal(scopedState.company_scope.version,1);
 assert.equal(scopedState.scope_history.length,1);
 assert.equal(scopedState.scope_history[0].before_value,null);
 assert.equal(scopedState.history.length,state.history.length,'scope audit must not enter rate history');
 await assert.rejects(saveScope(0),/scope version conflict/);
 assert.deepEqual(await read(),scopedState);
 // Trusted registration fixture: client lacks INSERT and cannot self-mark verified.
 await db.exec('reset role');
 await db.query(`insert into payroll_rate_private.candidates
 (company_id,candidate_id,item_id,value,scope_version,checked_at,verified_at,verified_by,verification_evidence)
 values($1,$2,$3,$4::jsonb,1,now(),now(),$5,'isolated fixture verification')`,
 [company,candidate,item,JSON.stringify(value),owner]);
 await actor(admin);
 state=await read();
 assert.equal(state.items.find(x=>x.item_id===item).version,2,'candidate registration never applies');
 assert.equal(state.candidates.length,1);
 await assert.rejects(apply(2,false),/confirmation required/);
 await assert.rejects(apply(1,true,candidate,company,untouched),/candidate not found/);
 await assert.rejects(apply(2,true,null),/candidate ID required/);
 await assert.rejects(apply(1),/version conflict/);
 const adopted=await apply(2);
 assert.equal(adopted.version,3);assert.equal(adopted.origin,'official_candidate');
 state=await read();
 assert.deepEqual(state.history.find(x=>x.item_id===item && x.version===3).before_value,nextValue);
 assert.equal(state.history.find(x=>x.item_id===item && x.version===3).candidate_id,candidate);
 const changedScope={...scope,insurer:'union',prefecture:'大阪府',employment_business:'general'};
 const nextScope=await saveScope(1,changedScope);
 assert.equal(nextScope.version,2);
 scopedState=await read();
 assert.equal(scopedState.scope_history.length,2);
 assert.deepEqual(scopedState.scope_history[0].before_value,scope);
 assert.deepEqual(scopedState.scope_history[0].after_value,changedScope);
 await assert.rejects(apply(3),/candidate company scope version conflict/);
 assert.deepEqual(await read(),scopedState,'changed company conditions must invalidate old candidate without writes');
 // Force a real audit INSERT failure after the settings UPDATE and prove rollback.
 await db.exec('reset role');
 await db.exec(`create function payroll_rate_private.fixture_audit_fail() returns trigger language plpgsql as $$
 begin raise exception 'synthetic audit unavailable'; end $$;
 create trigger fixture_audit_fail before insert on payroll_rate_private.history
 for each row execute function payroll_rate_private.fixture_audit_fail()`);
 await actor(admin);
 const beforeFailure=await read();
 await assert.rejects(save(3,nextValue),/synthetic audit unavailable/);
 assert.deepEqual(await read(),beforeFailure,'audit failure must roll back rate and history');
 await db.exec('reset role');
 await db.exec(`create trigger fixture_scope_audit_fail before insert on payroll_rate_private.scope_history
 for each row execute function payroll_rate_private.fixture_audit_fail()`);
 await actor(admin);
 await assert.rejects(saveScope(2,{insurer:'unconfigured',prefecture:null,employment_business:null}),/synthetic audit unavailable/);
 assert.deepEqual(await read(),beforeFailure,'scope audit failure must roll back scope and separate history');
 // Record the staged FK limitation; this is not company-delete compatibility proof.
 await db.exec('reset role');
 await assert.rejects(db.query('delete from public.companies where id=$1',[company]),/foreign key constraint/);
 assert.equal((await db.query('select count(*)::int as n from public.companies')).rows[0].n,2);
 console.log('PASS exact staged rate migration: owner/admin, worker/anon/account/company denial, explicit manual/candidate apply, fixed shares, version, selected item, scope/version invalidation, separate audit and rollback');
} finally {await db.close();}
