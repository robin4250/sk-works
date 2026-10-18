import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),worker=id(2),actor=id(3),partner=id(5);
try {
 await setupExpenseCostFixture(db);
 for(const file of ['20261012142138_expense_document_original_costs.sql','20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql'])
  await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(`insert into companies(id,tax_rate) values('${company}',10);
 insert into company_members values('${company}','${actor}','owner');
 insert into workers(id,company_id,name,user_id,partner_company_id) values('${worker}','${company}','検証社員','${actor}','${partner}');
 insert into partner_companies values('${partner}','${company}','検証下請け');
 insert into private.expense_approval_settings(company_id,approver_ids,revision) values('${company}',array['${actor}']::uuid[],1);
 set test.uid='${actor}';`);
 const row=async month=>(await db.query(`select to_jsonb(p) value from payment_certificates p where company_id=$1 and partner_company_id=$2 and period_start=$3`,[company,partner,`2026-${month}-01`])).rows[0].value;
 const hash=async source=>(await db.query('select md5($1::jsonb::text) value',[JSON.stringify(source)])).rows[0].value;
 async function approve(n,month,method){
 await db.query(`insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,submitted_at,description,amount_yen)
 values($1,$2,$3,'検証社員',$4,$5,$5::date+interval '1 hour','検証経費',1000)`,[id(n),company,worker,actor,`2026-${month}-01`]);
 await db.query(`select public.expense_confirm_review($1,$2,1,'approve','subcontractor',$3,$4,'')`,[id(n+100),id(n),partner,method]);
 }
 for(const [n,month,method] of [[10,'07','cash'],[11,'08','payroll'],[12,'09','paid'],[13,'10','cash']])await approve(n,month,method);
 await db.exec(`update payment_certificates set status='finalized' where period_start='2026-10-01'`);
 const legacyFrozen=await row('10');
 const ledgerBefore=(await db.query('select * from private.expense_amount_consumptions order by claim_id,purpose')).rows;
 const choicesBefore=(await db.query('select * from private.expense_settlement_choices order by claim_id')).rows;
 await db.exec(fs.readFileSync('docs/candidates/expense_payment_direction_v2_20261019.sql.review-only','utf8'));
 await db.exec(fs.readFileSync('docs/candidates/expense_payment_v1_draft_conversion_20261019.sql.review-only','utf8'));
 const original=await row('07');const originalHash=await hash(original);
 const request=(source,changes={})=>({cid:company,doc:source.id,subject:partner,month:source.period_start,revision:source.revision,source,hash:null,backup:'fixture-export-verified-restore',rollout:'fixture-supported-build-and-old-path-denied',...changes});
 async function convert(r){return (await db.query('select private.convert_payment_expense_v1_draft($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9) value',[r.cid,r.doc,r.subject,r.month,r.revision,JSON.stringify(r.source),r.hash??await hash(r.source),r.backup,r.rollout])).rows[0].value;}
 async function rejected(r,pattern){const before=await row('07');await assert.rejects(convert(r),pattern);assert.deepEqual(await row('07'),before);}
 await rejected(request(original),/rollout/);
 await db.exec(`create or replace function private.expense_cost_direction_v2_enabled(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${company}'::uuid$$`);
 await rejected(request(original),/rollout/);
 await db.exec(`create or replace function private.expense_direction_v2_client_rollout_verified(cid uuid) returns boolean language sql stable security invoker set search_path='' as $$select cid='${company}'::uuid$$`);
 for(const changes of [{cid:id(99)},{subject:id(99)},{month:'2026-08-01'},{revision:99},{hash:'0'.repeat(32)},{backup:''},{rollout:''}])await rejected(request(original,changes),/denied|scope|unchanged|request/);
 await db.exec(`set test.uid='${id(99)}'`);await rejected(request(original),/actor denied/);await db.exec(`set test.uid='${actor}'`);
 await db.exec(`begin;update payment_certificates set automatic_calculation=false where id='${original.id}'`);
 try{await assert.rejects(convert(request(await row('07'))),/automatic draft/);}finally{await db.exec('rollback');}
 await db.exec(`begin;insert into private.expense_amount_consumptions(claim_id,purpose,company_id,document_kind,document_id,document_revision,claim_revision,amount_yen,snapshot)
 values('${id(10)}','cost_recovery','${company}','paymentCertificate','${original.id}',1,2,1000,'{}')`);
 try{await assert.rejects(convert(request(original)),/consumed/);}finally{await db.exec('rollback');}
 await db.exec(`begin;update private.expense_claims set description='変更後' where id='${id(10)}'`);
 try{await assert.rejects(convert(request(original)),/unchanged automatic draft/);}finally{await db.exec('rollback');}
 const after=await convert(request(original));
 assert.equal(after.id,original.id);assert.equal(after.gross_amount,0);assert.equal(after.deductions,1000);assert.equal(after.net_amount,-1000);
 assert.equal(after.revision,original.revision+1);assert.equal(after.status,'draft');
 assert.equal(after.snapshot.expense_extra_source_version,undefined);
 assert.equal(after.snapshot.expense_cost_direction_v2.direction,'deduction');
 assert.equal(after.snapshot.expense_cost_direction_v2.document_revision,after.revision);
 assert.equal(after.snapshot.expense_cost_basis.gross_before_expense_yen,0);
 assert.deepEqual(await convert(request(original)),after,'exact command retry has no second revision/effect');
 const audit=(await db.query('select * from private.expense_payment_direction_conversions')).rows;
 await assert.rejects(db.exec('delete from private.expense_payment_direction_conversions'),/immutable/);
 await assert.rejects(db.exec("update private.expense_payment_direction_conversions set backup_reference='changed'"),/immutable/);
 assert.equal(audit.length,1);assert.deepEqual(audit[0].before_row,original);assert.deepEqual(audit[0].after_row,after);assert.equal(audit[0].source_hash,originalHash);
 await assert.rejects(convert(request(original,{backup:'changed'})),/retry differs/);
 await assert.rejects(convert(request(after)),/retry differs/);
 for(const month of ['08','09']){const source=await row(month);const result=await convert(request(source));assert.equal(result.net_amount,-1000);}
 assert.deepEqual((await db.query('select * from private.expense_settlement_choices order by claim_id')).rows,choicesBefore,'all three requester settlement methods stay byte-value identical');
 assert.deepEqual((await db.query('select * from private.expense_amount_consumptions order by claim_id,purpose')).rows,ledgerBefore,'conversion alone consumes nothing and preserves existing ledger');
 assert.deepEqual(await row('10'),legacyFrozen);await assert.rejects(convert(request(legacyFrozen)),/automatic draft/);
 const detail=(await db.query(`select public.read_expense_document('paymentCertificate',$1) value`,[after.id])).rows[0].value;
 assert.equal(detail.revision,after.revision);assert.equal(detail.frozen,false);assert.equal(detail.cost_recovery_amount_yen,1000);assert.deepEqual(detail.expense_cost_direction_v2,after.snapshot.expense_cost_direction_v2);
 await db.query(`update payment_certificates set status='finalized' where id=$1`,[after.id]);
 const ledger=(await db.query(`select * from private.expense_amount_consumptions where claim_id=$1`,[id(10)])).rows;
 assert.equal(ledger.length,1);assert.equal(ledger[0].document_revision,after.revision);assert.equal(ledger[0].amount_yen,1000);
 await assert.rejects(convert(request(original)),/retry differs/);
 assert.deepEqual((await db.query(`select * from private.expense_amount_consumptions where claim_id=$1`,[id(10)])).rows,ledger);
 const permissions=(await db.query(`select has_function_privilege('authenticated','private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)','execute') allowed`)).rows[0];assert.equal(permissions.allowed,false);
 console.log('PASS explicit original +1000 -> same draft -1000, exact full-row/hash/revision/scope/backup/rollout gates, no auto conversion, immutable backup+receipt retry, cash/payroll/paid unchanged, no consumption until finalize, one v2 consumption, finalized v1 preserved, private owner-only API');
}finally{await db.close();}
