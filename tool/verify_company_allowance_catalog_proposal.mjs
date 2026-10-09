// Isolated proposal verification. No production connection or migration runner.
import fs from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const db=new PGlite();
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const c='10000000-0000-0000-0000-000000000001', other='10000000-0000-0000-0000-000000000002';
const admin='20000000-0000-0000-0000-000000000001', worker='20000000-0000-0000-0000-000000000002';
const id='30000000-0000-0000-0000-000000000001', id2='30000000-0000-0000-0000-000000000002';
const actor=async value=>db.query("select set_config('fixture.uid',$1,false)",[value]);
const save=(company,item,version,name='通勤手当',unit='回',amount=500,active=true)=>db.query('select public.proposal_save_company_allowance_item($1,$2,$3,$4,$5,$6,$7) v',[company,item,version,name,unit,amount,active]);
try {
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('fixture.uid',true),'')::uuid $$;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.company_rate_settings(company_id uuid primary key,allowance_1_amount_yen bigint,allowance_1_name text,allowance_1_unit text,allowance_2_name text,allowance_2_unit text,allowance_3_name text,allowance_3_unit text);
 insert into company_rate_settings (company_id,allowance_1_amount_yen,allowance_1_name) values('${c}',777,'既存手当'),('${other}',888,'他社手当');
 insert into company_members values('${c}','${admin}','admin'),('${c}','${worker}','member');`);
 await db.exec(fs.readFileSync(path.join(root,'docs/payroll/proposals/company_allowance_catalog.sql'),'utf8'));
 await actor(admin); await db.exec('set role authenticated');
 assert.equal((await save(c,id,0)).rows[0].v,1); // Non-owner execution uses scoped definer authorization.
 await db.exec('reset role');
 const state=async()=>JSON.stringify((await db.query('select allowance_extra_catalog,allowance_catalog_version,(select jsonb_agg(l order by catalog_version) from payroll_allowance_private.change_log l) audit from company_rate_settings where company_id=$1',[c])).rows);
 const beforeFailures=await state();
 const legacyId=(await db.query('select public.proposal_read_company_allowance_labels($1) v',[c])).rows[0].v.items.find(x=>x.name==='既存手当').id;
 await assert.rejects(save(c,legacyId,1),/legacy slot must use existing company settings/);
 await assert.rejects(save(c,id2,1,' 通勤手当 '),/duplicate allowance name/);
 await assert.rejects(save(c,id2,1,'既存手当'),/duplicate allowance name/);
 await assert.rejects(save(c,id,0),/catalog version conflict/);
 await assert.rejects(save(other,id,0),/permission required/);
 await assert.rejects(save(c,id2,1,'別手当','円'),/invalid allowance fields/);
 await assert.rejects(save(c,id2,1,'別手当','回',-1),/invalid allowance fields/);
 await actor(worker); await db.exec('set role authenticated');
 await assert.rejects(save(c,id,1),/permission required/);
 await db.exec('reset role');
 await actor('20000000-0000-0000-0000-000000000099'); await db.exec('set role authenticated');
 await assert.rejects(save(c,id,1),/permission required/);
 await assert.rejects(db.query('select public.proposal_read_company_allowance_labels($1)',[c]),/membership required/);
 await db.exec('reset role'); assert.equal(await state(),beforeFailures); // Every rejected write is atomic.
 await actor(worker);
 await db.exec('set role authenticated');
 const read=(await db.query('select public.proposal_read_company_allowance_labels($1) v',[c])).rows[0].v;
 assert.equal(read.items.length,2); assert.deepEqual(read.items.find(x=>x.id===id),{id,name:'通勤手当',unit:'回',active:true});
 assert.ok(!JSON.stringify(read).includes('500')); assert.ok(!JSON.stringify(read).includes('amount'));
 await assert.rejects(db.query('select * from payroll_allowance_private.change_log'),/permission denied/);
 await assert.rejects(db.query('select public.proposal_read_company_allowance_labels($1)',[other]),/membership required/);
 await db.exec('reset role'); await actor(admin);
 await save(c,id,1,'通勤手当','回',900,false);
 assert.equal((await db.query('select public.proposal_read_company_allowance_labels($1) v',[c])).rows[0].v.items.length,1);
 // Retired identity and historical amount are retained, not deleted or converted to counts.
 const logs=(await db.query('select * from payroll_allowance_private.change_log order by catalog_version')).rows;
 assert.equal(logs.length,2); assert.equal(logs[0].after_catalog[0].amount_yen,500);
 assert.equal(logs[1].after_catalog[0].id,id); assert.equal(logs[1].actor_id,admin);
 assert.equal((await db.query('select allowance_1_amount_yen v from company_rate_settings where company_id=$1',[c])).rows[0].v,777);
 await db.query("update company_rate_settings set allowance_1_name='旧設定更新' where company_id=$1",[c]);
 const renamed=(await db.query('select public.proposal_read_company_allowance_labels($1) v',[c])).rows[0].v;
 assert.equal(renamed.items.find(x=>x.name==='旧設定更新').id,legacyId);
 const afterLegacyUpdate=await state();
 await assert.rejects(save(c,id,2),/catalog version conflict/);
 assert.equal(await state(),afterLegacyUpdate);
 await actor(''); await assert.rejects(db.query('select public.proposal_read_company_allowance_labels($1)',[c]),/membership required/);
 await db.exec('set role anon'); await assert.rejects(db.query('select public.proposal_read_company_allowance_labels($1)',[c]),/permission denied/);
 console.log('Company allowance catalog proposal: scope, projection, permissions, conflict, history and legacy preservation passed');
} finally {await db.close();}
