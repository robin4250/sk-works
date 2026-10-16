// Disposable in-memory SQL only; never accepts a database URL or real actor.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const read=p=>fs.readFileSync(p,'utf8');
const cid='10000000-0000-0000-0000-000000000001';
const actor='20000000-0000-0000-0000-000000000001';
const sid='70000000-0000-0000-0000-000000000001';
try {
 await db.exec(read('supabase/tests/company_allowance_identity_access_fixture.sql'));
 await db.exec(`create role service_role;create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);create function auth.jwt() returns jsonb language sql as $$select current_setting('request.jwt.claims')::jsonb$$;`);
 await db.query('insert into auth.sessions values($1,$2,null)',[sid,actor]);
 for(const file of ['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql'])await db.exec(read(`supabase/migrations/${file}`));
 await db.query("update public.company_rate_settings set allowance_1_name='足場手当',allowance_1_unit='組',allowance_2_name='安全手当',allowance_2_unit='本' where company_id=$1",[cid]);
 await db.exec(read('tool/staged_company_common_allowances.sql.review-only'));
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[actor,JSON.stringify({sub:actor,role:'authenticated',session_id:sid})]);
 await db.exec('set role authenticated');
 const units=async()=>(await db.query('select public.my_attendance_allowance_units() v')).rows[0].v;
 const state=async()=>(await db.query('select public.read_company_common_allowances_admin($1) v',[cid])).rows[0].v;
 let request=0;
 const save=async(s,legacy)=>(await db.query("select public.save_company_common_allowances($1,'daily',$2,$3::jsonb,$4,'[]'::jsonb,$5::jsonb,true) v",[cid,s.version,JSON.stringify(s.expected_source),`60000000-0000-4000-8000-${String(++request).padStart(12,'0')}`,JSON.stringify(legacy)])).rows[0].v;
 const refs=s=>s.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen}));
 const before=await units();let s=await state();s=await save(s,refs(s));
 let edit=refs(s);edit[0].name='改名後手当';s=await save(s,edit);const renamed=await units();
 edit=refs(s);edit[0].name=null;await save(s,edit);const retired=await units();
 for(const map of [before,renamed,retired]){assert.equal(map['足場手当'],'組');assert.equal(map['安全手当'],'本');assert.ok(Object.values(map).every(x=>typeof x==='string'));}
 fs.writeFileSync(process.argv[3],JSON.stringify({contract_version:1,before,renamed,retired}));
 console.log('PASS actual isolated RPC maps exported: original, renamed, retired; old names/units retained.');
} finally {await db.close();}
