// Review reproducer: demonstrates an unresolved origin ambiguity, not acceptance.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const root=new URL('../',import.meta.url);
try {
 for(const path of ['tool/fixtures/route_journey_capture/schema.sql','supabase/migrations/20261008204012_route_journey_capture_staged.sql','supabase/migrations/20261010132957_route_journey_visit_lifecycle.sql','supabase/migrations/20261010222139_route_manual_visit_capture.sql','supabase/migrations/20261012010000_route_final_visit_clock_out.sql']) await db.exec(await fs.readFile(new URL(path,root),'utf8'));
 await db.exec('alter table attendance_verifications add column confirmed_at timestamptz,add column attempted_at timestamptz');
 const id=n=>`40000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [company,actor,worker,route,stop,source,arrival,checkout]=[1,2,3,4,5,6,7,8].map(id);
 await db.query(`select set_config('test.uid',$1,false)`,[actor]);
 await db.query('insert into companies values($1)',[company]);
 await db.query("insert into company_members values($1,$2,'member')",[company,actor]);
 await db.query("insert into workers values($1,$2,$3,'fixture worker','active')",[worker,company,actor]);
 await db.query('insert into route_assignments values($1,$2)',[route,company]);
 await db.query("insert into route_stops values($1,$2,null,1,null,'fixture stop')",[stop,route]);
 await db.query("insert into attendance_verifications values($1,$2,$3,null,$4,'2000-01-01','clock_in',null,null,'manual',1,'2000-01-01T00:00Z','2000-01-01T00:00Z')",[source,company,worker,route]);
 await db.query('insert into private.route_journey_rollouts values($1,true)',[company]);
 await db.exec('grant insert on attendance_verifications to authenticated;set role authenticated');
 const payload=attempt=>({capture_contract_version:1,gps_capture_status:'missing',photo_capture_status:'missing',gps_captured_at:null,photo_captured_at:null,photo_observed_at:null,captured_address:null,latitude:null,longitude:null,accuracy_m:null,photo_storage_path:null,attempted_at:attempt});
 const save=async(capture,kind,start,attempt)=>(await db.query('select public.save_route_journey_visit($1,$2,$3,$4,$5,$6,$7) v',[capture,source,stop,'direct',payload(attempt),kind,start])).rows[0].v;
 const begun=await save(arrival,'start',arrival,'2000-01-01T01:00Z');
 // Authorized client can preselect the future checkout UUID and attempt time.
 const claimed=begun.recorded_at;
 const ended=await save(checkout,'end',arrival,claimed);
 await db.query("insert into attendance_verifications values($1,$2,$3,null,$4,'2000-01-01','clock_out',$5,null,'manual',1,$6,$6)",[checkout,company,worker,route,source,claimed]);
 await db.exec('reset role');
 const evidence=(await db.query(`select ec.id=o.id same_id,(ec.payload->>'attempted_at')::timestamptz=o.attempted_at same_attempt,
 ec.recorded_at>o.confirmed_at late_save,
 (ec.payload->>'attempted_at')::timestamptz>=sc.recorded_at attempt_after_arrival,
 (ec.payload->>'attempted_at')::timestamptz<=o.confirmed_at attempt_before_checkout
 from private.route_journey_captures ec join attendance_verifications o on o.id=ec.id
 join private.route_journey_captures sc on sc.id=$1 where ec.id=$2`,[arrival,checkout])).rows[0];
 assert.ok(Object.values(evidence).every(x=>x===true));
 assert.equal(ended.id,checkout);
 // This capture was explicitly saved before checkout, NOT by its BEFORE trigger.
 // Yet every identity/attempt predicate in the current candidate is satisfied.
 console.log('UNRESOLVED: preseeded end capture plus caller-selected checkout ID/times satisfies the proposed atomic identity predicate');
} finally {await db.close();}

