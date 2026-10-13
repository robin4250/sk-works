// Exact migrations in an isolated DB only. No production credentials or writes.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const owner='10000000-0000-0000-0000-000000000011';
const admin='10000000-0000-0000-0000-000000000012';
const worker='10000000-0000-0000-0000-000000000013';
const other='20000000-0000-0000-0000-000000000012';
const scope={insurer:'kyokai',prefecture:'東京都',employment_business:'construction'};
const sources={health_insurance:'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/rate_prefectures/r08/',nursing_insurance:'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/002/',child_support:'https://www.kyoukaikenpo.or.jp/about/business/insurance_rate/003/',pension_insurance:'https://www.nenkin.go.jp/service/kounen/hokenryo/ryogaku/ryogakuhyo/index.html',employment_insurance:'https://jsite.mhlw.go.jp/yamagata-roudoukyoku/koyouhoken-20260316.html'};
const values=Object.entries(sources).map(([kind,url])=>({kind,label:kind,total:1000000,employee:500000,employer:500000,insurance_month:'2026-10-01',payroll_month:'2026-10-01',payment_month:'2026-11-01',source:{url,publisher:'Official fixture',document_hash:'a'.repeat(64),applicability:{...scope,scope_version:'1',effective_insurance_month:'2026-04-01'}}}));
const clone=x=>JSON.parse(JSON.stringify(x));
async function role(name,id=owner){await db.exec('reset role');await db.query("select set_config('test.actor',$1,false)",[id]);await db.exec(`set role ${name}`);}
async function publish(batch=values,id=owner,version=1,c=company){return (await db.query('select public.publish_official_payroll_rate_candidates($1,$2,$3,$4::jsonb) r',[c,id,version,JSON.stringify(batch)])).rows[0].r;}
async function state(){await db.exec('reset role');return (await db.query(`select jsonb_build_object('settings',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from payroll_rate_private.settings s),'history',(select coalesce(jsonb_agg(to_jsonb(h)),'[]') from payroll_rate_private.history h),'scope',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from payroll_rate_private.company_scope s),'scope_history',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from payroll_rate_private.scope_history s)) s`)).rows[0].s;}
async function count(){await db.exec('reset role');return (await db.query('select count(*)::int n from payroll_rate_private.candidates')).rows[0].n;}
async function reject(batch,pattern=/./,id=owner,version=1,c=company){const before=await count();await role('service_role');await assert.rejects(publish(batch,id,version,c),pattern);assert.equal(await count(),before,'rejection must roll back entire batch');}
try {
 await db.exec(fs.readFileSync('supabase/tests/company_payroll_rate_registry_bootstrap.sql','utf8'));
 await db.exec('create role service_role; create table private.account_deletion_access_restrictions(user_id uuid primary key,job_id uuid not null,restricted_at timestamptz not null); alter table private.account_deletion_access_restrictions enable row level security;');
 await db.exec(fs.readFileSync('supabase/migrations/20261009151946_company_payroll_rate_registry.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261010041129_official_payroll_rate_candidates.sql','utf8'));
 const signature='public.publish_official_payroll_rate_candidates(uuid,uuid,bigint,jsonb)';
 for(const r of ['anon','authenticated','service_role']){const q=await db.query('select has_function_privilege($1,$2,\'EXECUTE\') ok',[r,signature]);assert.equal(q.rows[0].ok,r==='service_role');}
 for(const r of ['anon','authenticated']){await role(r);await assert.rejects(publish(),/permission denied/);}
 await role('authenticated');await db.query('select public.save_company_payroll_rate_scope($1,0,$2::jsonb,true)',[company,JSON.stringify(scope)]);
 // Keep a pre-existing manually saved setting intact during fetch.
 await db.query('select public.save_manual_company_payroll_rate($1,\'health_insurance\',0,$2::jsonb,true)',[company,JSON.stringify(values[0])]);
 const before=await state();
 for(const id of [worker,other,null]) await reject(values,/access denied/,id);
 await reject(values,/access denied/,owner,1,'00000000-0000-0000-0000-000000000001');
 await db.query('insert into private.account_deletion_access_restrictions values($1,gen_random_uuid(),now())',[admin]);
 await reject(values,/access denied/,admin);
 await db.exec('reset role');await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[admin]);
 await reject(values,/scope version conflict/,owner,2);
 await reject([],/1 to 5/);await reject(null,/array/);await reject([...values,values[0]],/1 to 5/);
 await reject([values[0],values[0]],/duplicate/);
 for(const mutation of [v=>v.insurance_month='2026-03-01',v=>v.kind='custom',v=>v.total++,v=>v.source.document_hash='invalid',v=>v.source.url+='?untrusted=1',v=>v.source.applicability.scope_version='2',v=>v.source.applicability.prefecture='大阪府',v=>delete v.source.applicability.effective_insurance_month]){const v=clone(values[0]);mutation(v);await reject([values[1],v]);}
 const employment=clone(values[4]);employment.source.applicability.employment_business='general';await reject([employment],/business differs/);
 const wrongInsurer=clone(values[1]);wrongInsurer.source.applicability.insurer='union';await reject([wrongInsurer],/insurer scope differs/);
 await role('service_role');assert.deepEqual(await publish(values,admin),{count:5});
 assert.deepEqual(await state(),before,'publication must leave settings/history/scope untouched');
 assert.equal(await count(),5);
 const evidence=(await db.query('select * from payroll_rate_private.candidates order by item_id')).rows;
 for(const row of evidence){assert.equal(row.verified_by,admin);assert.equal(row.scope_version,1);assert.match(row.verification_evidence,/official-rate-parser-v1; sha256=/);assert.ok(row.checked_at);}
 await role('service_role');assert.deepEqual(await publish(),{count:5});assert.equal(await count(),10,'refetch retains old evidence');
 await role('authenticated');const latest=(await db.query('select public.read_company_payroll_rates($1) r',[company])).rows[0].r;
 const candidate=latest.candidates.find(c=>c.item_id==='health_insurance');assert.ok(candidate);
 const applied=(await db.query('select public.apply_company_payroll_rate_candidate($1,$2,$3,1,true) r',[company,candidate.item_id,candidate.candidate_id])).rows[0].r;
 assert.equal(applied.origin,'official_candidate');assert.equal(applied.version,2);
 await db.query('select public.save_company_payroll_rate_scope($1,1,$2::jsonb,true)',[company,JSON.stringify({...scope,prefecture:'大阪府'})]);
 await reject(values,/scope version conflict/);
 console.log('PASS official candidates: service-only ACL, owner/admin/restricted/company denial, scope CAS, bounded atomic batches, hash/URL/scope validation, immutable settings/audit, retained evidence and explicit normal apply');
} finally {await db.close();}
