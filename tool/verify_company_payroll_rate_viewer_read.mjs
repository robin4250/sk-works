import fs from 'node:fs';import assert from 'node:assert/strict';
const{PGlite}=await import(process.argv[2]);const db=new PGlite();const readFile=p=>fs.readFileSync(p,'utf8');
const company='10000000-0000-0000-0000-000000000001',other='20000000-0000-0000-0000-000000000001',owner='10000000-0000-0000-0000-000000000011',admin='10000000-0000-0000-0000-000000000012',viewer='10000000-0000-0000-0000-000000000014',worker='10000000-0000-0000-0000-000000000013',manager='10000000-0000-0000-0000-000000000015',otherViewer='20000000-0000-0000-0000-000000000014',unregistered='10000000-0000-0000-0000-000000000016',candidate='40000000-0000-0000-0000-000000000001',item='employment_insurance';
const scope={insurer:'kyokai',prefecture:'東京都',employment_business:'construction'};
const value={kind:'employment_insurance',label:'Fixture employment',total:777777,employee:123456,employer:654321,insurance_month:'2030-04-01',payroll_month:'2030-05-01',payment_month:'2030-06-01',source:{url:'https://example.test/fixture.pdf',publisher:'Fixture source',document_hash:'fixture-hash',applicability:{business:'fixture'}}};
const nextValue={...value,total:888888,employee:234567};
async function actor(id,role='authenticated',allowed=true){await db.exec('reset role');await db.query("select set_config('test.actor',$1,false),set_config('test.account_allowed',$2,false)",[id,String(allowed)]);await db.exec(`set role ${role}`);}
async function read(c=company){return(await db.query('select public.read_company_payroll_rates($1) as result',[c])).rows[0].result;}
async function save(){return db.query('select public.save_manual_company_payroll_rate($1,$2,1,$3::jsonb,true)',[company,item,JSON.stringify(nextValue)]);}
async function saveScope(){return db.query('select public.save_company_payroll_rate_scope($1,1,$2::jsonb,true)',[company,JSON.stringify(scope)]);}
async function apply(){return db.query('select public.apply_company_payroll_rate_candidate($1,$2,$3,1,true)',[company,item,candidate]);}
try{
 await db.exec(readFile('supabase/tests/company_payroll_rate_registry_bootstrap.sql'));
 await db.exec(readFile('supabase/migrations/20261009151946_company_payroll_rate_registry.sql'));
 await db.exec(readFile('supabase/tests/company_payroll_rate_viewer_fixture.sql'));
 await actor(owner);await db.query('select public.save_company_payroll_rate_scope($1,0,$2::jsonb,true)',[company,JSON.stringify(scope)]);await db.query('select public.save_manual_company_payroll_rate($1,$2,0,$3::jsonb,true)',[company,item,JSON.stringify(value)]);
 await db.exec('reset role');await db.query('insert into payroll_rate_private.candidates values($1,$2,$3,$4::jsonb,now(),1,now(),$5,$6)',[company,candidate,item,JSON.stringify(nextValue),owner,'Synthetic trusted evidence only']);
 await actor(admin);const before=await read();
 await db.exec('reset role');const original=(await db.query("select pg_get_functiondef('payroll_rate_private.read_rates(uuid)'::regprocedure) as definition")).rows[0].definition;
 const writesBefore=(await db.query("select proname,md5(prosrc) as hash,proacl from pg_proc where pronamespace='payroll_rate_private'::regnamespace and proname in ('require_admin','write_rate','save_scope') order by proname")).rows;
 await db.exec("create or replace function payroll_rate_private.read_rates(p_company_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return '{}';end$$");
 await assert.rejects(db.exec(readFile('supabase/migrations/20261009183439_company_payroll_rate_viewer_read.sql')),/prerequisite differs/);
 assert.equal((await db.query("select to_regprocedure('payroll_rate_private.require_reader(uuid)') as fn")).rows[0].fn,null);
 await db.exec(original);await db.exec(readFile('supabase/migrations/20261009183439_company_payroll_rate_viewer_read.sql'));
 assert.deepEqual((await db.query("select proname,md5(prosrc) as hash,proacl from pg_proc where pronamespace='payroll_rate_private'::regnamespace and proname in ('require_admin','write_rate','save_scope') order by proname")).rows,writesBefore);
 await actor(admin);assert.deepEqual(await read(),{...before,can_edit:true});await actor(owner);assert.deepEqual(await read(),{...before,can_edit:true});
 await actor(viewer);const visible=await read();assert.equal(visible.can_edit,false);assert.deepEqual(visible.items,before.items);assert.deepEqual(visible.candidates,before.candidates);assert.deepEqual(visible.history,[]);assert.deepEqual(visible.scope_history,[]);const{updated_by,...scopePublic}=before.company_scope;assert.deepEqual(visible.company_scope,scopePublic);assert.equal('updated_by'in visible.company_scope,false);
 for(const call of[save,saveScope,apply])await assert.rejects(call(),/admin access denied/);
 await assert.rejects(db.query('select * from payroll_rate_private.history'),/permission denied/);await assert.rejects(db.query('select payroll_rate_private.require_reader($1)',[company]),/permission denied/);
 assert.deepEqual(await read(),visible,'viewer loads and refused writes do not change settings/history');
 for(const id of[otherViewer,unregistered,worker,manager,'']){await actor(id);await assert.rejects(read(),/reader access denied/);}
 await actor(viewer);await assert.rejects(read(other),/reader access denied/);await actor(viewer,'authenticated',false);await assert.rejects(read(),/reader access denied/);
 await actor(viewer,'anon');await assert.rejects(read(),/permission denied/);
 await actor(admin);await apply();let approved=await read();assert.equal(approved.items[0].version,2);assert.equal(approved.history.length,2);assert.equal(approved.history[0].actor_id,admin);assert.equal(approved.can_edit,true);
 await actor(viewer);assert.deepEqual((await read()).items,approved.items);
 await db.exec('reset role');assert.equal((await db.query("select has_function_privilege('authenticated','payroll_rate_private.require_reader(uuid)','execute') as allowed")).rows[0].allowed,false);
 await db.query('delete from public.companies where id=$1',[company]);
 assert.equal((await db.query('select count(*)::int as n from payroll_rate_private.history where company_id=$1',[company])).rows[0].n,2);
 for(const id of[owner,admin,viewer]){await actor(id);await assert.rejects(read(),/reader access denied/);}
 await actor(otherViewer);assert.deepEqual(await read(other),{items:[],candidates:[],history:[],company_scope:null,scope_history:[],can_edit:false});
 console.log('PASS rate viewer reader: exact source refusal, unchanged admin/write contract, scoped viewer read/write denial, actor projection, fallback/nonmember/account/anonymous/deleted-company refusal, historical retention');
}catch(e){console.error(e.message,e.where||'');process.exitCode=1;}finally{await db.close();}
