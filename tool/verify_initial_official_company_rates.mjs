// Disposable DB only; production data and credentials are not used.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const owner='10000000-0000-0000-0000-000000000011';
const worker='10000000-0000-0000-0000-000000000013';
const scope={insurer:'kyokai',prefecture:'東京都',employment_business:'construction'};
async function role(name,id=owner){await db.exec('reset role');await db.query("select set_config('test.actor',$1,false)",[id]);await db.exec(`set role ${name}`);}
async function initialize(ids,fallback=false,version=1){return (await db.query('select public.initialize_official_company_rates($1,$2,$3::jsonb,$4) r',[company,version,JSON.stringify(ids),fallback])).rows[0].r;}
async function state(){await db.exec('reset role');return (await db.query("select jsonb_build_object('settings',(select coalesce(jsonb_agg(to_jsonb(s) order by item_id),'[]') from payroll_rate_private.settings s),'history',(select coalesce(jsonb_agg(to_jsonb(h) order by item_id),'[]') from payroll_rate_private.history h)) s")).rows[0].s;}
try {
 await db.exec(fs.readFileSync('supabase/tests/company_payroll_rate_registry_bootstrap.sql','utf8'));
 await db.exec('create role service_role; create table private.account_deletion_access_restrictions(user_id uuid primary key,job_id uuid not null,restricted_at timestamptz not null);');
 for(const name of ['20261009151946_company_payroll_rate_registry','20261010041129_official_payroll_rate_candidates','20261010150706_initial_official_company_rates'])await db.exec(fs.readFileSync(`supabase/migrations/${name}.sql`,'utf8'));
 const dates=(await db.query("select date_trunc('month',clock_timestamp() at time zone 'Asia/Tokyo')::date::text m,(date_trunc('month',clock_timestamp() at time zone 'Asia/Tokyo')+interval '1 month')::date::text p")).rows[0];
 const urls={health_insurance:'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/rate_prefectures/r08/',nursing_insurance:'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/002/',pension_insurance:'https://www.nenkin.go.jp/service/kounen/hokenryo/ryogaku/ryogakuhyo/index.html',employment_insurance:'https://jsite.mhlw.go.jp/yamagata-roudoukyoku/koyouhoken-20260316.html'};
 const values=Object.entries(urls).map(([kind,url])=>({kind,label:kind,total:1000000,employee:500000,employer:500000,insurance_month:dates.m,payroll_month:dates.m,payment_month:dates.p,source:{url,publisher:'Official fixture',document_hash:'a'.repeat(64),applicability:{...scope,scope_version:'1',effective_insurance_month:'2026-04-01'}}}));
 await role('authenticated');await db.query('select public.save_company_payroll_rate_scope($1,0,$2::jsonb,true)',[company,JSON.stringify(scope)]);
 await role('service_role');await db.query('select public.publish_official_payroll_rate_candidates($1,$2,1,$3::jsonb)',[company,owner,JSON.stringify(values)]);
 await db.exec('reset role');const candidates=(await db.query('select item_id,candidate_id from payroll_rate_private.candidates')).rows;
 const ids=Object.fromEntries(candidates.map(c=>[c.item_id,c.candidate_id]));
 const before=await state();
 for(const actor of [worker,'20000000-0000-0000-0000-000000000012']){await role('authenticated',actor);await assert.rejects(initialize(ids),/access denied/);}
 await role('anon');await assert.rejects(initialize(ids,true),/permission denied/);
 await role('authenticated');await assert.rejects(initialize(ids,false,2),/scope/);
 await assert.rejects(initialize({...ids,employment_insurance:'00000000-0000-0000-0000-000000000000'}),/fresh/);
 assert.deepEqual(await state(),before,'invalid last candidate rolls back first three rates/audit');
 await role('authenticated');await assert.rejects(initialize({...ids,child_support:ids.health_insurance}),/four/);
 await db.exec('reset role');await db.exec("update payroll_rate_private.candidates set checked_at=clock_timestamp()-interval '11 minutes'");
 await role('authenticated');await assert.rejects(initialize(ids),/fresh/);
 await db.exec('reset role');await db.exec('update payroll_rate_private.candidates set checked_at=clock_timestamp()');
 await role('authenticated');await db.exec('begin');
 assert.deepEqual(await initialize(ids),{initialized:true,fallback:false});
 const official=await state();assert.equal(official.settings.length,4);assert.equal(official.history.length,4);assert.ok(official.settings.every(s=>s.origin==='official_candidate'));
 await role('authenticated');assert.deepEqual(await initialize({},true),{initialized:false});assert.deepEqual(await state(),official,'fallback/rerun preserves existing rates and history');
 await db.exec('rollback');
 await role('authenticated');assert.deepEqual(await initialize({},true),{initialized:true,fallback:true});
 const defaults=await state();assert.equal(defaults.settings.length,4);assert.equal(defaults.history.length,4);
 for(const s of defaults.settings){assert.equal(s.origin,'manual');assert.equal(s.value.source.applicability.verification,'最新未確認');assert.equal(s.value.insurance_month,dates.m);assert.equal(s.value.payment_month,dates.p);assert.notEqual(s.item_id,'child_support');}
 assert.deepEqual(Object.fromEntries(defaults.settings.map(s=>[s.item_id,s.value.total])),{health_insurance:9900000,nursing_insurance:1620000,pension_insurance:18300000,employment_insurance:1650000});
 await role('authenticated');assert.deepEqual(await initialize(ids),{initialized:false});assert.deepEqual(await state(),defaults,'saved reference values also require explicit later update');
 console.log('PASS initial rates: ACL, fresh evidence, scope CAS, atomic rollback, official/reference modes, unchanged existing rates, four items only');
} finally {await db.close();}
