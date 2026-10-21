// Disposable synthetic fixture only. Never opens a remote DB or creates JWT claims.
import fs from 'node:fs';import assert from 'node:assert/strict';import {fileURLToPath,pathToFileURL}from'node:url';
const here=fileURLToPath(new URL('.',import.meta.url));
const repo=process.argv[2];const runtime=process.argv[3];if(!repo||!runtime)throw Error('explicit local fixture dependencies required');
process.chdir(repo);const {setupExpenseCostFixture}=await import(pathToFileURL(repo+'/tool/fixtures/expense_cost_fixture.mjs'));
const {PGlite}=await import(pathToFileURL(runtime));const db=new PGlite();const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const C=id(1),W=id(2),O=id(3),P=id(5),LOGIN='cli_login_maintenance_fixture';let checks=0;
const check=(a,b)=>{assert.deepEqual(a,b);checks++};const deny=async(fn,p)=>{await assert.rejects(fn,p);checks++};
const q=async(s,a=[])=>(await db.query(s,a)).rows[0]?.v;
try{
 await setupExpenseCostFixture(db);
 await db.exec("do $$begin if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role;end if;end $$");
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.query('insert into companies(id,tax_rate)values($1,10)',[C]);await db.query("insert into company_members values($1,$2,'owner')",[C,O]);
 await db.query("insert into workers(id,company_id,name,user_id,partner_company_id)values($1,$2,'合成社員',$3,$4)",[W,C,O,P]);await db.query("insert into partner_companies values($1,$2,'合成下請')",[P,C]);
 // Seed synthetic approved original data directly as DB owner; never simulate app auth.
 await db.query("insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen,approval,allocation,counterparty_id,counterparty_name,revision)values($1,$2,$3,'合成社員',$4,'2026-07-01','2026-07-01','合成経費',1000,'approved','subcontractor',$5,'合成下請',2)",[id(10),C,W,O,P]);
 await db.query("insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current)values($1,$2,'cash','2026-07-01',2,$3,true,true)",[id(10),C,O]);
 await db.query(`insert into payment_certificates(id,company_id,partner_company_id,period_start,period_end,gross_amount,deductions,net_amount,snapshot)
 select $1,$2,$3,'2026-07-01','2026-07-31',1000,0,1000,jsonb_build_object('expense_extra_source_version',1,'expense_extra_amount_yen',1000,'expense_extra_claims',private.expense_cost_components('paymentCertificate',$2,$3,'2026-07-01','2026-07-31',null)->'claims','calculation_rows','[]'::jsonb)`,[id(20),C,P]);
 const original=await q('select to_jsonb(p)v from payment_certificates p where company_id=$1',[C]);check(original.net_amount,1000);
 await db.exec(fs.readFileSync(here+'source/candidate.sql','utf8'));await db.exec(fs.readFileSync(here+'source/conversion.sql','utf8'));
 const originalCatalog=await q("select jsonb_build_object('function',pg_get_functiondef('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)'::regprocedure),'table',(select jsonb_agg(to_jsonb(a))from pg_attribute a where attrelid='private.expense_payment_direction_conversions'::regclass and attnum>0))v");
 await db.exec('begin');await db.exec(originalCatalog.function.replace('begin\n','begin\n -- fixture unknown source drift\n'));
 await deny(()=>db.exec(fs.readFileSync(here+'maintenance.sql.review-only','utf8')),/original converter source differs/);await db.exec('rollback');
 check(await q("select to_regclass('private.expense_payment_maintenance_conversions')v"),null);
 await db.exec(fs.readFileSync(here+'maintenance.sql.review-only','utf8'));
 check(await q('select auth.uid()v'),null);
 const authority=await q('select to_jsonb(m)v from company_members m where company_id=$1',[C]);const hash=await q('select md5($1::jsonb::text)v',[JSON.stringify(original)]);
 const request={cid:C,doc:original.id,subject:P,month:'2026-07-01',rev:original.revision,source:original,hash,backup:'synthetic-protected-before',rollout:'synthetic-build7-source-proof',login:LOGIN,authority,authorization:'a'.repeat(64)};
 const convert=(changes={})=>{const r={...request,...changes};return q('select private.convert_payment_expense_v1_maintenance($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11::jsonb,$12)v',[r.cid,r.doc,r.subject,r.month,r.rev,JSON.stringify(r.source),r.hash,r.backup,r.rollout,r.login,JSON.stringify(r.authority),r.authorization]);};
 const state=()=>q("select jsonb_build_object('row',(select to_jsonb(p)from payment_certificates p where id=$1),'claims',(select jsonb_agg(to_jsonb(x))from private.expense_claims x),'choices',(select jsonb_agg(to_jsonb(x))from private.expense_settlement_choices x),'consumptions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from private.expense_amount_consumptions x),'old_audit',(select count(*)from private.expense_payment_direction_conversions),'maintenance',(select count(*)from private.expense_payment_maintenance_conversions))v",[original.id]);
 const before=await state();await deny(()=>convert(),/executor denied/);check(await state(),before);
 await db.exec(`create role ${LOGIN} superuser login;set session authorization ${LOGIN};set role postgres`);
 check(await q('select auth.uid()v'),null);await deny(()=>convert(),/rollout/);check(await state(),before);
 await db.exec(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid)returns boolean language sql stable security invoker set search_path=''as $$select cid='${C}'::uuid$$;create or replace function private.expense_direction_v2_client_rollout_verified(cid uuid)returns boolean language sql stable security invoker set search_path=''as $$select cid='${C}'::uuid$$`);
 for(const changes of [{authorization:''},{login:'postgres'},{authority:{...authority,role:'admin'}},{authority:{...authority,user_id:id(99)}},{hash:'0'.repeat(32)},{rev:999},{subject:id(99)},{backup:''},{rollout:''}]){await deny(()=>convert(changes),/denied|authorization|original|scope|request|unchanged|no rows/);check(await state(),before);}
 // Mutations below are disposable setup transactions, rolled back after rejection.
 for(const change of ["automatic_calculation=false","calculation_blocked=true","status='finalized'","gross_amount=999"]){
  await db.exec('begin');try{await db.query('update payment_certificates set '+change+' where id=$1',[original.id]);const changed=await q('select to_jsonb(p)v from payment_certificates p where id=$1',[original.id]);const changedHash=await q('select md5($1::jsonb::text)v',[JSON.stringify(changed)]);await deny(()=>convert({source:changed,hash:changedHash}),/automatic draft|basis differs/);}finally{await db.exec('rollback')};check(await state(),before);
 }
 await db.exec('begin');try{await db.query("insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)values($1,'cost_recovery',$2,'paymentCertificate',$3,1,2,1000,'{}')",[id(10),C,original.id]);await deny(()=>convert(),/consumed/);}finally{await db.exec('rollback')};check(await state(),before);
 // Real transaction rollback around a later failure preserves both target and receipt.
 await db.exec("create function private.fixture_maintenance_late_failure()returns trigger language plpgsql as $$begin raise exception 'late receipt failure';end $$;create trigger fixture_maintenance_late_failure before insert on private.expense_payment_maintenance_conversions for each row execute function private.fixture_maintenance_late_failure()");
 await deny(()=>convert(),/late receipt failure/);check(await state(),before);await db.exec('drop trigger fixture_maintenance_late_failure on private.expense_payment_maintenance_conversions');
 const after=await convert();check(after.gross_amount,0);check(after.deductions,1000);check(after.net_amount,-1000);check(after.revision,original.revision+1);check(after.status,'draft');check(after.snapshot.expense_cost_direction_v2.claims,[{id:id(10),revision:2,amount_yen:1000}]);
 check(await convert(),after);const final=await state();check(final.maintenance,1);check(final.old_audit,0);check(final.claims,before.claims);check(final.choices,before.choices);check(final.consumptions,before.consumptions);
 const receipt=await q('select to_jsonb(m)v from private.expense_payment_maintenance_conversions m');check(receipt.execution_kind,'maintenance');check(receipt.db_session_user,LOGIN);check(receipt.db_current_user,'postgres');check(Object.hasOwn(receipt,'actor_id'),false);check(receipt.authority_original,authority);check(receipt.authorization_reference,request.authorization);
 await deny(()=>convert({authorization:'b'.repeat(64)}),/retry differs/);await deny(()=>db.exec('delete from private.expense_payment_maintenance_conversions'),/immutable/);await deny(()=>db.exec('update private.expense_payment_maintenance_conversions set source_revision=source_revision'),/immutable/);
 check(await q("select jsonb_build_object('function',pg_get_functiondef('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)'::regprocedure),'table',(select jsonb_agg(to_jsonb(a))from pg_attribute a where attrelid='private.expense_payment_direction_conversions'::regclass and attnum>0))v"),originalCatalog);
 await db.exec('reset role;reset session authorization');for(const role of ['authenticated','anon','service_role']){await db.exec('set role '+role);await deny(()=>convert(),/permission denied/);await db.exec('reset role');}
 check(await q('select auth.uid()v'),null);check(await q("select current_setting('request.jwt.claims',true)v"),null);
 console.log('PASS '+checks+' maintenance checks; null app identity, distinct DB executor, atomic rollback, exact before/CAS/replay, immutable separate receipt, original converter unchanged; synthetic only');
}catch(e){console.error({message:e.message,detail:e.detail,where:e.where});process.exitCode=1;}finally{await db.close()}
