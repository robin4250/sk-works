import fs from 'node:fs';
import assert from 'node:assert/strict';
import {setupExpenseCostFixture} from './fixtures/expense_cost_fixture.mjs';
const {PGlite} = await import(process.argv[2]);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const company=id(1), worker=id(2), applicant=id(3), owner=id(10), admin=id(11),
  manager=id(12), viewer=id(13), unassigned=id(14), outsider=id(15), employee=id(16), otherCompany=id(20);
const read = path => fs.readFileSync(path, 'utf8');
const candidate='docs/candidates/expense_notifications_20261019.sql.review-only';
let checks=0;
function pass(label) { checks++; console.log(`PASS ${checks}: ${label}`); }
async function actor(value) { await db.exec(`set test.uid='${value ?? ''}'`); }
async function count(table='public.app_notifications') {
  return Number((await db.query(`select count(*) n from ${table}`)).rows[0].n);
}
async function submit(n, {creator=applicant, wid=worker, cid=company, amount=1234}={}) {
  await actor(creator);
  return (await db.query('select public.expense_personal_submit($1,$2,$3,$4,$5,$6) value',
    [id(n),cid,wid,'2026-09-30','SYNTHETIC_PRIVATE_DESCRIPTION',amount])).rows[0].value;
}
async function confirm(command, claim, {action='approve', category='ownCompany', method='payroll', revision=1, party=null}={}) {
  await actor(owner);
  return (await db.query('select public.expense_confirm_review($1,$2,$3,$4,$5,$6,$7,$8) value',
    [id(command),id(claim),revision,action,category,party,method,'SYNTHETIC_PRIVATE_MEMO'])).rows[0].value;
}
async function notice(key, target, recipient) {
  const rows=(await db.query('select * from app_notifications where action_key=$1 and action_id=$2 and recipient_user_id=$3',
    [key,target,recipient])).rows;
  assert.equal(rows.length,1); return rows[0];
}
async function target(noticeId, who) {
  await actor(who);
  await db.exec('set role authenticated');
  try { return (await db.query('select public.expense_notification_target($1) value',[noticeId])).rows[0].value; }
  finally { await db.exec('reset role'); }
}
async function denied(noticeId, who) {
  await assert.rejects(target(noticeId,who), error => error.code==='42501');
}
try {
  await setupExpenseCostFixture(db);
  for(const file of ['20261012142138_expense_document_original_costs.sql',
    '20261012163343_expense_settlement_application_month.sql','20261012170840_expense_atomic_review_flow.sql']) {
    await db.exec(read('supabase/migrations/'+file));
  }
  await db.exec('create table auth.users(id uuid primary key)');
  const notificationSource=read('supabase/migrations/20260919213000_add_app_notifications.sql');
  const enqueueBoundary='create or replace function private.enqueue_notification(';
  assert.equal(notificationSource.split(enqueueBoundary).length,2);
  await db.exec(notificationSource.slice(0,notificationSource.indexOf(enqueueBoundary)));
  const enqueue=notificationSource.slice(notificationSource.indexOf(enqueueBoundary));
  const end=enqueue.indexOf('\n$$;');assert.ok(end>0);
  await db.exec(enqueue.slice(0,end+4));
  await db.exec(`revoke all on function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
    grant select on app_notifications to authenticated;
    insert into companies(id,tax_rate) values('${company}',10),('${otherCompany}',10);
    insert into auth.users(id) values ${[applicant,owner,admin,manager,viewer,unassigned,outsider,employee].map(v=>`('${v}')`).join(',')};
    insert into company_members values
      ('${company}','${applicant}','employee'),('${company}','${owner}','owner'),('${company}','${admin}','admin'),
      ('${company}','${manager}','manager'),('${company}','${viewer}','viewer'),('${company}','${unassigned}','manager'),
      ('${company}','${employee}','employee'),('${otherCompany}','${outsider}','owner');
    insert into workers(id,company_id,name,user_id) values('${worker}','${company}','SYNTHETIC_PRIVATE_NAME','${applicant}');
    insert into private.expense_approval_settings(company_id,approver_ids,revision)
      values('${company}',array['${owner}','${manager}','${viewer}']::uuid[],1);`);
  const protectedNames=['private.expense_personal_submit(uuid,uuid,uuid,date,text,integer)',
    'private.expense_confirm_review(uuid,uuid,integer,text,text,uuid,text,text)',
    'private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)',
    'private.refresh_automatic_payment_certificate(uuid,uuid,date)','private.refresh_automatic_invoice(uuid,uuid,date)'];
  async function definitions() {
    return Promise.all(protectedNames.map(async name=>(await db.query('select pg_get_functiondef($1::regprocedure) value',[name])).rows[0].value));
  }
  const before=await definitions();
  await db.exec(read(candidate));
  assert.deepEqual(await definitions(),before);
  pass('candidate keeps existing submit/confirm/enqueue/invoice/payment function definitions unchanged');

  await submit(100);
  assert.deepEqual((await db.query('select recipient_user_id from app_notifications order by recipient_user_id')).rows.map(r=>r.recipient_user_id),
    [owner,admin,manager,viewer].sort());
  assert.equal((await db.query('select count(*)::int n from app_notifications where recipient_user_id=$1',[worker])).rows[0].n,0);
  pass('submission notifies same-company owners/admins and assigned manager/viewer only; worker UUID is never a recipient');
  const firstCount=await count();
  await submit(100); assert.equal(await count(),firstCount);
  await assert.rejects(submit(100,{amount:9999}), error=>error.code==='23505');
  assert.equal(await count(),firstCount);
  pass('fixed submission retry and conflicting retry create no duplicate notices');

  const request=await notice('expense_review_request',id(100),owner);
  const requestTarget=await target(request.id,owner);
  assert.equal(requestTarget.claim_id,id(100));assert.equal(requestTarget.claim.amount_yen,1234);
  assert.equal(requestTarget.claim.description,'SYNTHETIC_PRIVATE_DESCRIPTION');
  await denied(request.id,outsider);await denied(request.id,applicant);await denied(id(999),owner);await denied(request.id,null);
  pass('exact saved notification ID resolves only for its recipient, current same-company authorization and account');

  async function forged(n,recipient,cid=company,key='expense_review_request',action=id(100)) {
    await db.query('insert into app_notifications(id,company_id,recipient_user_id,title,action_key,action_id) values($1,$2,$3,$4,$5,$6)',
      [id(n),cid,recipient,'fixture forged notice',key,action]);
  }
  await forged(401,unassigned);await denied(id(401),unassigned);
  await forged(402,outsider,otherCompany);await denied(id(402),outsider);
  await forged(403,owner,company,'settings');await denied(id(403),owner);
  await db.exec(`update company_members set role='employee' where company_id='${company}' and user_id='${owner}'`);
  await denied(request.id,owner);
  await db.exec(`update company_members set role='owner' where company_id='${company}' and user_id='${owner}'`);
  pass('forged known notice target cannot bypass reviewer/company/action checks or current role revocation');

  const result=await confirm(200,100);
  const complete=await notice('expense_review_completed',id(200),applicant);
  const completeTarget=await target(complete.id,applicant);
  assert.equal(completeTarget.claim.revision,2);assert.equal(completeTarget.claim.settlement_method,'payroll');
  assert.equal(completeTarget.action_id,id(200));assert.equal(completeTarget.claim_id,id(100));
  const approvedCount=await count();
  assert.deepEqual(await confirm(200,100),result);assert.equal(await count(),approvedCount);
  await assert.rejects(confirm(200,100,{method:'cash'}),error=>error.code==='23505');assert.equal(await count(),approvedCount);
  pass('approved atomic receipt sends one applicant notice; fixed command replay returns the same receipt without another notice');

  await submit(101);
  const beforeRejected=await count();
  await confirm(201,101,{action:'reject',category:null,method:null});
  assert.equal(await count(),beforeRejected);
  await submit(102);
  const beforeFailed=await count();
  await assert.rejects(confirm(202,102,{category:'customer',party:id(999)}));
  assert.equal(await count(),beforeFailed);
  assert.equal((await db.query('select approval from private.expense_claims where id=$1',[id(102)])).rows[0].approval,'pending');
  pass('rejected confirmation and failed final validation do not create completion notices');

  await actor(owner);
  await db.query('select public.expense_review_edit($1,$2,$3,$4,$5,$6)',[id(203),id(100),2,'2026-09-30','NEW_CURRENT_DESCRIPTION',4321]);
  assert.equal((await target(complete.id,applicant)).claim.description,'SYNTHETIC_PRIVATE_DESCRIPTION');
  assert.equal((await target(complete.id,applicant)).claim.amount_yen,1234);
  assert.equal((await target(request.id,owner)).claim.description,'NEW_CURRENT_DESCRIPTION');
  assert.equal((await db.query("select count(*)::int n from app_notifications where action_key='expense_review_completed' and action_id=$1",[id(203)])).rows[0].n,0);
  pass('completion uses immutable confirmation snapshot after later edit; request uses current row and edit creates no completion notice');

  const beforeRollback=await count();
  await db.exec('begin');
  try { await submit(103);await db.exec('select 1/0'); }
  catch { await db.exec('rollback'); }
  assert.equal(await count(),beforeRollback);
  assert.equal((await db.query('select count(*)::int n from private.expense_claims where id=$1',[id(103)])).rows[0].n,0);
  pass('submission and its notices roll back together when the containing operation fails');

  await submit(104);
  const beforeNoticeFailure=await count();
  await db.exec(`create function public.fixture_fail_completion() returns trigger language plpgsql as $$begin
    if new.action_key='expense_review_completed' then raise exception 'fixture delivery failure';end if;return new;end$$;
    create trigger fixture_fail_completion before insert on app_notifications for each row execute function public.fixture_fail_completion();`);
  await assert.rejects(confirm(204,104),/fixture delivery failure/);
  assert.equal(await count(),beforeNoticeFailure);
  assert.equal((await db.query('select revision from private.expense_claims where id=$1',[id(104)])).rows[0].revision,1);
  assert.equal((await db.query('select count(*)::int n from private.expense_review_confirmations where command_id=$1',[id(204)])).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from private.expense_settlement_choices where claim_id=$1',[id(104)])).rows[0].n,0);
  await db.exec('drop trigger fixture_fail_completion on app_notifications;drop function public.fixture_fail_completion()');
  pass('enqueue failure rolls back approval, settlement, receipt and notification, rather than committing partial success');

  const withdrawnNotice=await notice('expense_review_request',id(102),owner);
  await actor(applicant);
  await db.query("select public.expense_personal_change($1,$2,1,'withdraw',null,null,null)",[id(207),id(102)]);
  await denied(withdrawnNotice.id,owner);
  pass('withdrawn current requests are unavailable instead of appearing as a received claim');

  await db.query('insert into customers(id,company_id,name,notes) values($1,$2,$3,$4)',
    [id(30),company,'SYNTHETIC_CUSTOMER','']);
  await submit(105);
  await confirm(205,105,{category:'customer',method:'paid',party:id(30)});
  const generated=(await db.query('select id from invoices where customer_id=$1',[id(30)])).rows[0];
  assert.ok(generated);
  await db.query("update invoices set snapshot=snapshot||jsonb_build_object('signature_secret','SYNTHETIC_PRIVATE_SIGNATURE'),status='finalized' where id=$1",[generated.id]);
  const frozen=(await db.query('select to_jsonb(i) value from invoices i where id=$1',[generated.id])).rows[0].value;
  await submit(106);await confirm(206,106,{method:'cash'});
  assert.deepEqual((await db.query('select to_jsonb(i) value from invoices i where id=$1',[generated.id])).rows[0].value,frozen);
  const externalComplete=await notice('expense_review_completed',id(205),applicant);
  assert.equal((await target(externalComplete.id,applicant)).claim.counterparty_name,'SYNTHETIC_CUSTOMER');
  assert.ok(!JSON.stringify(await target(externalComplete.id,applicant)).includes('SYNTHETIC_PRIVATE_SIGNATURE'));
  pass('existing finalized financial snapshot stays byte-equivalent through unrelated notices; signature data is not returned');

  const notices=(await db.query("select * from app_notifications where action_key in ('expense_review_request','expense_review_completed') and title <> 'fixture forged notice'")).rows;
  for(const n of notices) {
    assert.ok(!JSON.stringify([n.title,n.body]).includes('SYNTHETIC_PRIVATE'));
    assert.ok(!JSON.stringify([n.title,n.body]).includes('1234'));
  }
  const allowedKeys=['id','company_id','applicant_name','incurred_on','submitted_at','description','amount_yen','approval',
    'allocation','counterparty_name','settlement_method','settlement_month','reviewed_at','review_memo','revision'].sort();
  assert.deepEqual(Object.keys(completeTarget.claim).sort(),allowedKeys);
  for(const privateKey of ['created_by','applicant_id','receipt_object_path','signature','actor_id','command','reviewed_by']) {
    assert.equal(Object.hasOwn(completeTarget.claim,privateKey),false);
  }
  await actor(unassigned);await db.exec('set role authenticated');
  try {
    const own=(await db.query('select recipient_user_id from app_notifications')).rows;
    assert.ok(own.every(r=>r.recipient_user_id===unassigned));
    await assert.rejects(db.exec('select private.expense_claim_notice_insert()'),error=>error.code==='42501');
  } finally { await db.exec('reset role'); }
  await actor(owner);await db.exec('set role anon');
  try {await assert.rejects(db.query('select public.expense_notification_target($1)',[request.id]),error=>error.code==='42501');}
  finally {await db.exec('reset role');}
  pass('notice bodies contain no claim PII; reader whitelists summary fields; saved own-notification RLS and new API ACL remain enforced in fixture');

  await db.exec(`delete from company_members where company_id='${company}' and user_id='${applicant}'`);
  await denied(complete.id,applicant);
  await db.exec("create or replace function private.account_access_allowed() returns boolean language sql as $$select false$$");
  await denied(request.id,owner);
  assert.equal(await count('payroll_statements'),0);
  pass('membership/account revocation denies old summary links; no payroll statement is generated');
  console.log(`PASS expense notification review-only candidate: ${checks} boundary groups; synthetic PGlite only`);
} finally { await db.close(); }
