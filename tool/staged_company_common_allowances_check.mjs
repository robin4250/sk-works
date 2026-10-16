// Disposable synthetic SQL fixture. No project connection, secrets, data or network.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const originalMigrations=['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql'];
let db;
if(process.argv[3]==='--pg17'){
 const url=new URL(process.env.SKO_COMMON_ALLOWANCE_FIXTURE_URL??'');
 assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/sko_common_allowance_fixture');
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);
 db=new(mod.Client??mod.default.Client)({connectionString:url.href});await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal(Math.floor(Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private','auth') and c.relkind='r'")).rows[0].n,0);
}else{const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();}
const cid='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
const admin='20000000-0000-0000-0000-000000000001',member='20000000-0000-0000-0000-000000000002',viewer='20000000-0000-0000-0000-000000000003',otherOwner='20000000-0000-0000-0000-000000000004';
const uuid=n=>`40000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
let requestN=0;
const actor=async(id=admin,role='authenticated',blocked=false)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('fixture.account_blocked',$2,false)",[id,blocked?'true':'']);await db.exec(`set role ${role}`);};
const state=async(company=cid)=>(await db.query('select public.read_company_common_allowances_admin($1) v',[company])).rows[0].v;
const save=async(version,items,{type='daily',rid=uuid(++requestN),company=cid}={})=>(await db.query('select public.save_company_common_allowances($1,$2,$3,$4,$5::jsonb) v',[company,type,version,rid,JSON.stringify(items)])).rows[0].v;
const receipt=async rid=>(await db.query('select public.read_company_common_allowance_request($1,$2) v',[cid,rid])).rows[0].v;
const history=async(before=null,limit=50)=>(await db.query('select public.read_company_common_allowances_history($1,$2,$3) v',[cid,before,limit])).rows[0].v;
const item=(key='new-unit-item-0',overrides={})=>({id:null,client_key:key,section:'earning',unit:'day',name:'同名',amount_yen:700,...overrides});
const existing=(i,key='existing')=>({id:i.id,client_key:key,section:i.section,unit:i.unit,name:i.name,amount_yen:i.amount_yen});
async function protectedSnapshot(){await db.exec('reset role');return (await db.query(`select jsonb_build_object(
 'companies',(select jsonb_agg(to_jsonb(x) order by id) from public.companies x),
 'members',(select jsonb_agg(to_jsonb(x) order by company_id,user_id) from public.company_members x),
 'settings',(select jsonb_agg(to_jsonb(x) order by company_id) from public.company_rate_settings x),
 'payroll',(select jsonb_agg(to_jsonb(x) order by id) from public.payroll_statements x),
 'legacy_state',(select jsonb_agg(to_jsonb(x) order by company_id) from company_allowance_identity_private.state x),
 'legacy_identities',(select jsonb_agg(to_jsonb(x) order by id) from company_allowance_identity_private.identities x),
 'legacy_history',(select jsonb_agg(to_jsonb(x) order by company_id,version) from company_allowance_identity_private.history x),
 'daily',(select jsonb_agg(to_jsonb(x) order by id) from public.fixture_daily x)) v`)).rows[0].v;}
try{
 await db.exec(read('supabase/tests/company_allowance_identity_access_fixture.sql'));await db.exec('create role service_role');
 for(const m of originalMigrations)await db.exec(read(`supabase/migrations/${m}`));
 await db.exec("create table public.fixture_daily(id uuid primary key,quantity jsonb,signature text);insert into public.fixture_daily values('50000000-0000-4000-8000-000000000001','{\"units\":2}','synthetic-signature')");
 await actor();const legacy=(await db.query('select public.read_company_allowance_identity_admin($1) v',[cid])).rows[0].v;
 await db.query('select public.adopt_company_allowance_identity($1,$2::jsonb,true)',[cid,JSON.stringify(legacy.observed_slots)]);
 const before=await protectedSnapshot();
 const candidate=read('tool/staged_company_common_allowances.sql.review-only');await db.exec(candidate);
 await actor();let s=await state();assert.equal(s.version,0);assert.equal(s.items.length,0);assert.equal(s.legacy_unassigned.length,3);assert.equal(s.legacy_unassigned[0].name,s.legacy_unassigned[1].name);
 assert.equal(s.can_edit,true);assert.deepEqual(await protectedSnapshot(),before,'DDL/read never backfill or alter existing configuration');
 await actor();const rid=uuid(++requestN),payload=[item(),item('second',{amount_yen:800,unit:'hour'}),item('third',{section:'deduction',unit:'month'})];
 s=await save(0,payload,{rid});assert.equal(s.version,1);assert.equal(s.committed_version,1);assert.equal(s.id_map.length,3);assert.equal(s.items.length,3);assert.equal(new Set(s.items.map(i=>i.id)).size,3,'same names remain distinct IDs');
 const stable=s.items[0].id,retire=s.items[1].id;
 const saved=structuredClone(s);assert.deepEqual(await save(0,payload,{rid}),saved,'same request replay returns original receipt without another version');
 const rec=await receipt(rid);assert.equal(rec.found,true);assert.equal(rec.actor_id,admin);assert.deepEqual(rec.request_payload,{payroll_type:'daily',expected_version:0,items:payload});assert.deepEqual(rec.result,saved);
 assert.equal((await receipt(uuid(999))).found,false,'not found is unresolved, not rollback evidence');
 await assert.rejects(save(0,[],{rid}),e=>e.code==='22023');
 await assert.rejects(save(0,payload),e=>e.code==='40001');assert.deepEqual(await state(),((({request_id,committed_version,id_map,...rest})=>rest)(saved)));
 let next=s.items.filter(x=>x.id!==retire).map((x,i)=>existing(x,`keep-${i}`));next[0].name='改名';next[0].amount_yen=900;
 s=await save(1,next);assert.equal(s.items.find(x=>x.name==='改名').id,stable);
 await db.exec('reset role');assert.equal((await db.query('select retired_by from company_common_allowance_private.items where id=$1',[retire])).rows[0].retired_by,admin);
 await actor();await assert.rejects(save(2,[item('retired',{id:retire})]),e=>e.code==='22023');
 const current=s.items.map((x,i)=>existing(x,`old-${i}`));s=await save(2,[...current,item('replacement')]);assert.notEqual(s.items.at(-1).id,retire);
 const dailyIds=s.items.map(x=>x.id);s=await save(3,[item('hourly')],{type:'hourly'});assert.equal(s.items.filter(x=>x.payroll_type==='daily').length,3);assert.deepEqual(s.items.filter(x=>x.payroll_type==='daily').map(x=>x.id),dailyIds);
 const foreign=s.items.find(x=>x.payroll_type==='hourly').id;await assert.rejects(save(4,[item('wrong',{id:foreign})]),e=>e.code==='22023');
 await assert.rejects(save(4,[item('dup'),item('dup')]),e=>e.code==='22023');
 const d=s.items.find(x=>x.payroll_type==='daily');await assert.rejects(save(4,[existing(d,'one'),existing(d,'two')]),e=>e.code==='22023');
 for(const invalid of [item('bad',{name:''}),item('bad',{name:'x'.repeat(81)}),item('bad',{amount_yen:-1}),item('bad',{amount_yen:1.5}),item('bad',{amount_yen:'1'}),item('bad',{amount_yen:2147483648}),item('bad',{unit:'回'}),item('bad',{section:'unknown'}),item('bad',{id:uuid(900)}),item('bad',{extra:true}),item('bad key')]){
  await assert.rejects(save(4,[invalid]),e=>e.code==='22023');
 }
 await assert.rejects(save(4,Array.from({length:101},(_,i)=>item(`n${i}`))),e=>e.code==='22023');
 await assert.rejects(save(4,[item('bad',{name:'x'.repeat(132000)})]),e=>e.code==='22023');
 for(const uid of [member,otherOwner,'']){await actor(uid);await assert.rejects(state(),e=>e.code==='42501');await assert.rejects(save(4,[]),e=>e.code==='42501');await assert.rejects(history(),e=>e.code==='42501');}
 await actor(viewer);s=await state();assert.equal(s.can_edit,false);assert.equal(s.version,4);assert.ok((await history()).entries.length>0);await assert.rejects(save(4,[]),e=>e.code==='42501');await assert.rejects(receipt(rid),e=>e.code==='42501');
 await actor(admin,'authenticated',true);await assert.rejects(state(),e=>e.code==='42501');await assert.rejects(save(4,[]),e=>e.code==='42501');
 await actor(admin,'anon');await assert.rejects(state(),e=>e.code==='42501');
 await actor();await assert.rejects(state(other),e=>e.code==='42501');await assert.rejects(save(0,[],{company:other}),e=>e.code==='42501');
 await db.exec('reset role');await db.query("update public.company_members set role='manager' where company_id=$1 and user_id=$2",[cid,admin]);
 await actor();await assert.rejects(state(),e=>e.code==='42501');await assert.rejects(save(4,[]),e=>e.code==='42501');
 await db.exec('reset role');await db.query("update public.company_members set role='admin' where company_id=$1 and user_id=$2",[cid,admin]);
 await actor();for(const table of ['state','items','history','requests'])await assert.rejects(db.query(`select * from company_common_allowance_private.${table}`),e=>e.code==='42501');
 await db.exec('reset role');await db.exec("create function company_common_allowance_private.fail_history() returns trigger language plpgsql as $$begin raise exception 'fixture audit unavailable';end$$;create trigger fail_history before insert on company_common_allowance_private.history for each row execute function company_common_allowance_private.fail_history()");
 await actor();const preFail=await state(),failRid=uuid(++requestN);await assert.rejects(save(4,[item('should-rollback')],{rid:failRid}),/fixture audit unavailable/);assert.deepEqual(await state(),preFail);assert.equal((await receipt(failRid)).found,false);
 await db.exec('reset role');await db.exec('drop trigger fail_history on company_common_allowance_private.history');
 await actor();for(let n=0;n<102;n++)await save(4+n,[item(`page-${n}`)],{type:'monthly'});
 const h=await history(null,100);assert.equal(h.entries.length,100);assert.ok(h.before_version>1);const older=await history(h.before_version,100);assert.equal(older.entries.at(-1).version,1);assert.equal(older.entries.at(-1).actor_id,admin);assert.ok(older.entries.at(-1).after_value.some(x=>x.id===retire),'retired source remains in history');
 assert.deepEqual((await receipt(rid)).result,saved,'late receipt retains exact original result despite later edits');
 await assert.rejects(history(null,101),e=>e.code==='22023');assert.deepEqual(await protectedSnapshot(),before,'all old columns, old random identities/history, finalized statements, daily/signature and admin/company identities remain exact');
 // Restore pre-candidate source by dropping ONLY the new isolated schema/APIs.
 const rollback=`drop function public.read_company_common_allowances_admin(uuid);drop function public.save_company_common_allowances(uuid,text,bigint,uuid,jsonb);drop function public.read_company_common_allowance_request(uuid,uuid);drop function public.read_company_common_allowances_history(uuid,bigint,integer);drop schema company_common_allowance_private cascade;`;
 const backup={};for(const t of ['state','items','history','requests'])backup[t]=(await db.query(`select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) v from company_common_allowance_private.${t} x`)).rows[0].v;
 await db.exec(rollback);assert.deepEqual(await protectedSnapshot(),before);
 await db.exec(candidate);await actor();assert.equal((await state()).items.length,0);assert.deepEqual(await protectedSnapshot(),before);
 await db.exec('reset role');for(const t of ['state','items','history','requests'])await db.query(`insert into company_common_allowance_private.${t} select * from jsonb_populate_recordset(null::company_common_allowance_private.${t},$1::jsonb)`,[JSON.stringify(backup[t])]);
 await actor();assert.equal((await state()).version,106);assert.deepEqual((await receipt(rid)).result,saved);assert.deepEqual(await protectedSnapshot(),before,'isolated backup restoration preserves old identities and data');
 console.log('PASS additive company allowance contract: real legacy migration coexistence, zero implicit copy, stable UUID/retirement, type isolation, CAS/receipt recovery, strict limits, viewer/admin boundaries, rollback and exact old configuration/payroll/daily/admin preservation. Synthetic auth fixture, not live JWT or production proof.');
}catch(e){console.error(e.stack);process.exitCode=1;}finally{await db.close();}
