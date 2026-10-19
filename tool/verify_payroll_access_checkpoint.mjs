import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
// PGlite only: never accepts a database URL or a native PostgreSQL adapter.
assert.ok(path.isAbsolute(process.argv[2]??'')&&process.argv[2].endsWith('/@electric-sql/pglite/dist/index.js'),'Absolute pinned PGlite index path required');
assert.ok(path.isAbsolute(process.argv[3]??''),'Absolute trusted private checkpoint path required');
const checkpoint=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const expected=new Set(['payroll_scope_private.lock_scopes(jsonb,boolean)','payroll_tax_private.calculate(uuid,uuid,date,date,bigint,bigint)','private.account_access_allowed()','private.has_company_feature(uuid,text)','private.payroll_allowed(uuid,text)','private.payroll_approver_ids(uuid)','private.payroll_settings_allowed(uuid,uuid,text)','private.sync_payroll_attendance_detail(uuid,uuid,date)','resident_tax_private.resolve(uuid,uuid,date)']);
assert.equal(checkpoint.format,'sko-payroll-helper-checkpoint-v1');
assert.equal(checkpoint.functions?.length,expected.size);
assert.deepEqual(new Set(checkpoint.functions.map(f=>f.signature)),expected);
for(const f of checkpoint.functions){assert.match(f.body_md5,/^[a-f0-9]{32}$/);assert.equal(typeof f.definition,'string');}
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',editor='00000000-0000-0000-0000-000000000002',viewer='00000000-0000-0000-0000-000000000003',manager='00000000-0000-0000-0000-000000000005',professional='00000000-0000-0000-0000-000000000006';
const actor=async(id,role='authenticated')=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role);};
const read=p=>fs.readFileSync(p,'utf8');
try{
 await setupPayrollScopeFixture(db);
 for(const name of ['20261009171504_payroll_refresh_scope_order.sql','20261009151946_company_payroll_rate_registry.sql','20261010030208_connect_payroll_tax_calculation.sql','20261013175452_payroll_unit_conditions.sql','20261014033249_payroll_fixed_deduction_overrides.sql','20261018215043_fix_payroll_null_work_category.sql'])await db.exec(read('supabase/migrations/'+name));
 await db.exec(`create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_view_admin_site_data boolean default false,can_manage_admin_site_data boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
 create table public.payroll_approvers(company_id uuid,user_id uuid,position integer);
 create table private.professional_invites(company_id uuid,claimed_by uuid,status text,payroll_access text);`);
 const names=['has_company_feature','payroll_approver_ids','payroll_allowed','payroll_settings_allowed','account_access_allowed'];
 for(const name of names){
  const entry=checkpoint.functions.find(x=>x.signature.startsWith('private.'+name+'('));assert.ok(entry);
  await db.exec('alter function '+entry.signature+' rename to synthetic_old_'+name);
 }
 for(const name of names){
  const entry=checkpoint.functions.find(x=>x.signature.startsWith('private.'+name+'('));
  await db.exec(entry.definition);
  // These are fixture grants, not a replay or certification of production ACLs.
  await db.exec('revoke all on function '+entry.signature+' from public,anon;grant execute on function '+entry.signature+' to authenticated');
 }
 for(const entry of checkpoint.functions){
  const actual=(await db.query("select md5(prosrc) body_md5,prosecdef,provolatile,proconfig from pg_proc where oid=to_regprocedure($1)",[entry.signature])).rows[0];
  for(const key of ['body_md5','prosecdef','provolatile','proconfig'])assert.deepEqual(actual[key],entry[key],entry.signature+' '+key);
 }
 console.log('PASS nine direct helper bodies/security/volatility/search_path match the limited read-only catalog checkpoint; owner/ACL/full closure not asserted');
 await db.exec(read('docs/candidates/payroll_single_draft_recalculation_20261019.sql.review-only'));
 await db.exec(read('docs/candidates/payroll_single_draft_preview_20261019.sql.review-only'));
 await db.exec(`delete from public.attendance_entries;delete from public.payroll_statements;delete from public.payroll_adjustments;update public.worker_payroll_settings set pay_type='daily',day_daily=20000,custom_earnings='[]',custom_deductions='[]',family_monthly=0,transport_monthly=0,income_tax_monthly=0,social_insurance_monthly=0,resident_tax_monthly=0,other_deduction_monthly=0 where worker_id='${wid}';`);
 await db.query("insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days) values(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001','2026-09-12',null,1)",[cid,wid]);
 const ps=(await db.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2026-09-01'",[cid,wid])).rows[0];assert.ok(ps);
 const preview=async()=>(await db.query('select public.preview_one_payroll_draft($1,$2,$3,$4,$5) result',[ps.id,ps.revision,cid,wid,'2026-09-01'])).rows[0].result;
 const unchanged=async()=>{await db.exec('reset role');assert.deepEqual((await db.query('select * from public.payroll_statements where id=$1',[ps.id])).rows[0],ps);};
 await db.query('insert into auth.users(id) values($1),($2)',[manager,professional]);
 await db.query("insert into public.company_members(company_id,user_id,role) values($1,$2,'manager')",[cid,manager]);
 for(const id of[owner,editor]){await actor(id);const p=await preview();assert.equal(p.projected_calculation,null);await unchanged();}
 for(const id of[viewer,manager,'']){await actor(id);await assert.rejects(preview(),e=>e.code==='42501');await unchanged();}
 console.log('PASS exact checkpoint helpers: owner/editor allowed; viewer, manager without payroll grant and anonymous refused; draft unchanged');
 await db.query('insert into public.member_feature_permissions(company_id,user_id,can_manage_payroll) values($1,$2,true)',[cid,manager]);
 await actor(manager);await preview();await unchanged();
 await db.query('update public.member_feature_permissions set can_manage_payroll=false where user_id=$1',[manager]);
 await actor(manager);await assert.rejects(preview(),e=>e.code==='42501');await unchanged();
 await db.query('insert into public.payroll_access(company_id,user_id,can_view,can_edit) values($1,$2,true,true)',[cid,manager]);
 await actor(manager);await preview();await unchanged();
 await db.query('update public.payroll_access set can_edit=false where user_id=$1',[manager]);
 await actor(manager);await assert.rejects(preview(),e=>e.code==='42501');await unchanged();
 console.log('PASS explicit company feature grant or payroll edit grant required; revocation/refusal leaves draft unchanged');
 await actor(editor);const before=await preview();await db.exec('reset role');
 await db.query('insert into private.account_deletion_access_restrictions(user_id) values($1)',[editor]);
 await actor(editor);await assert.rejects(preview(),e=>e.code==='42501');
 await assert.rejects(db.query('select public.recalculate_one_payroll_draft($1,$2,$3,$4,$5,true,$6)',[ps.id,ps.revision,cid,wid,'2026-09-01',before.expected_source]),e=>e.code==='42501');await unchanged();
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[editor]);await actor(editor);await preview();await unchanged();
 console.log('PASS actual account-restriction predicate rejects preview and apply, removal permits preview; no salary update');
 await db.query("insert into private.professional_invites(company_id,claimed_by,status,payroll_access) values($1,$2,'approved','view')",[cid,professional]);
 await actor(professional);assert.equal((await db.query("select private.payroll_allowed($1,'view') allowed",[cid])).rows[0].allowed,true);
 await assert.rejects(preview(),e=>e.code==='42501');await unchanged();
 console.log('PASS approved professional view access cannot become draft-repair edit access; synthetic tables/Auth.uid only, not live JWT or full RLS');
}catch(error){console.error(error.message);process.exitCode=1;}finally{await db.close();}
