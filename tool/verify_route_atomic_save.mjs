import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {schema,A,B,U,V,R,S1,S2,ST1,ST2,C} from './route_atomic_fixture.mjs';
const {PGlite}=await import(process.argv[2]??'@electric-sql/pglite');
const db=new PGlite();
await db.exec(schema);
await db.exec(await fs.readFile(new URL('./staged/route_atomic_save.sql',import.meta.url),'utf8'));
const q=(s,p=[])=>db.query(s,p);
const snapshot=async()=> (await q('select route_atomic_private.snapshot($1,$2) s',[A,R])).rows[0].s;
const all=async()=>JSON.stringify((await q(`select
(select jsonb_agg(r order by id) from route_assignments r) routes,
(select jsonb_agg(s order by id) from route_stops s) stops,
(select jsonb_agg(a order by id) from attendance_verifications a) attendance,
(select jsonb_agg(d order by id) from daily_reports d) reports,
(select jsonb_agg(c order by id) from private.route_journey_captures c) captures,
(select jsonb_agg(v order by id) from private.route_visit_reports v) visits`)).rows);
const cmd=n=>`00000000-0000-4000-9000-${String(n).padStart(12,'0')}`;
const stops=[{id:ST1,site_id:S1,address:'old A',source_kind:'site',source_id:S1},{id:ST2,address:'old B',source_kind:'address'}];
const data={route_name:'new name',notes:'new notes'};
const save=async(expected,ss=stops,n=1,company=A,route=R,dd=data)=>(await q('select route_atomic_private.save($1,$2,$3,$4,$5,$6) s',[company,cmd(n),route,expected,dd,ss])).rows[0].s;
async function rejects(fn,code){await assert.rejects(fn,e=>e.code===code);}
let p=await snapshot(), before=await all();
await rejects(()=>save(p),'55000');assert.equal(await all(),before);
await db.exec(`insert into route_atomic_private.rollout values('${A}',true) on conflict(company_id) do update set enabled=true`);
// Late stop failure occurs after route metadata UPDATE; entire transaction reverts.
await db.exec("select set_config('test.fail_stop','yes',false)");
await rejects(()=>save(p,[...stops,{address:'new location',source_kind:'address'}]),'P0001');
assert.equal(await all(),before);
assert.equal((await q('select count(*)::int n from route_atomic_private.receipts')).rows[0].n,0);
assert.equal((await q('select count(*)::int n from route_atomic_private.context')).rows[0].n,0);
await db.exec("select set_config('test.fail_stop','no',false)");
let result=await save(p);assert.equal(result.route.route_name,'new name');
assert.deepEqual(result.stops.map(s=>s.id),[ST1,ST2]);
assert.deepEqual(await save(p),result);
await rejects(()=>save(p,stops,2),'40001');
await rejects(()=>save(p,stops,1,A,R,{route_name:'different'}),'22023');
p=await snapshot();result=await save(p,[stops[1],stops[0]],3);
assert.deepEqual(result.stops.map(s=>s.id),[ST2,ST1]);
assert.deepEqual(result.stops.map(s=>s.stop_order),[0,1]);
p=await snapshot();before=await all();
await rejects(()=>save(p,[{...stops[0],site_id:S2,source_id:S2}],4),'42501');assert.equal(await all(),before);
await rejects(()=>save(p,[{address:'bad parking',source_kind:'parking',source_id:S2}],4),'42501');
await rejects(()=>save(p,[{address:'bad gps',source_kind:'address',latitude:91,longitude:1}],4),'22023');
await rejects(()=>save(p,stops,4,A,R,{route_name:'x',responsible_phone:'1'.repeat(41)}),'22023');
await db.exec(`select set_config('test.actor','${V}',false)`);
await rejects(()=>save(p,stops,4),'42501');
await db.exec(`insert into company_members values('${A}','${V}','admin')`);
await rejects(()=>save(p,stops,4),'40001');
await rejects(()=>save(p,stops,1),'22023');
await db.exec(`delete from company_members where company_id='${A}' and user_id='${V}'`);
await db.exec(`select set_config('test.actor','${U}',false);update company_members set role='viewer' where user_id='${U}'`);
await rejects(()=>save(p,stops,4),'42501');
await db.exec(`update company_members set role='manager' where user_id='${U}'`);
p=await snapshot();result=await save(p,[stops[1],stops[0]],5);
assert.equal(result.route.updated_by,U); // existing manager permission remains.
await db.exec("select set_config('test.feature','off',false)");
await rejects(()=>save(result,[stops[1],stops[0]],6),'55000');
await db.exec("select set_config('test.feature','on',false)");
await db.exec(`insert into private.route_journey_captures(company_id,route_assignment_id,route_stop_id,payload) values('${A}','${R}','${ST1}','{"saved":"evidence"}')`);
p=await snapshot();before=await all();
await rejects(()=>save(p,[stops[1]],6),'55000');assert.equal(await all(),before);
await rejects(()=>save(p,[stops[0],stops[1]],6),'55000');assert.equal(await all(),before);
await db.exec("select set_config('test.fail_stop','yes',false)");
await rejects(()=>save(p,[stops[1],stops[0],{address:'late failure with old history',source_kind:'address'}],6,A,R,{route_name:'must rollback',notes:'must rollback'}),'P0001');
assert.equal(await all(),before);
await db.exec("select set_config('test.fail_stop','no',false)");
await db.exec(`insert into attendance_verifications(company_id,route_assignment_id) values('${A}','${R}')`);
p=await snapshot();before=await all();
await rejects(()=>save(p,[stops[1],stops[0],{address:'append',source_kind:'address'}],6),'55000');
assert.equal(await all(),before);
// Direct client-chosen GUC does not create a private transaction capability.
await db.exec("select set_config('route_atomic.context','yes',false)");
await rejects(()=>q('update route_assignments set notes=$1 where id=$2',['legacy overwrite',R]),'55000');
assert.equal(await all(),before);
await rejects(()=>q('update route_assignments set company_id=$1 where id=$2',[B,R]),'55000');
assert.equal(await all(),before);
// OFF legacy operation is accepted without changing old functional behavior.
await db.exec('update route_atomic_private.rollout set enabled=false');
await q('update route_assignments set notes=$1 where id=$2',['legacy works',R]);
assert.equal((await snapshot()).route.notes,'legacy works');
await db.exec('update route_atomic_private.rollout set enabled=true');
const added=await save(null,[{address:'new parking',source_kind:'parking',source_id:C,latitude:35.1,longitude:139.1}],20,A,null,{route_name:'created',responsible_name:'manager',responsible_phone:'090'});
assert.notEqual(added.route.id,R);assert.equal(added.stops.length,1);
assert.equal((await snapshot()).route.notes,'legacy works');
assert.equal((await q("select has_schema_privilege('authenticated','route_atomic_private','usage') v")).rows[0].v,false);
assert.equal((await q("select has_table_privilege('authenticated','route_atomic_private.context','insert') v")).rows[0].v,false);
console.log('atomic route: late failure rollback, exact snapshot CAS, command recovery, stable stop IDs/order, history/tenant/role/feature/coordinates/parking/length guards, private context and OFF legacy compatibility passed; isolated fixture only');
await db.close();

