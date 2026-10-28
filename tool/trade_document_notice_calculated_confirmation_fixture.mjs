// Isolated actual daily calculator -> durable notice -> financial/seal command.
// Existing source/notice/financial functions are unchanged. Auth remains a fixture,
// and route/expense are explicitly empty; a second scenario uses real adjustments.
export async function verifyCalculatedNoticeConfirmation(db,c,prepareSource){
 const {A,B,UA,id,q,check,pending}=c;
 const before=await q('select to_jsonb(i) v from public.invoices i where id=$1',[pending.parent]);
 const counts=()=>q(`select jsonb_build_object(
  'audit',(select count(*) from invoice_approval_audit where invoice_id=$1),
  'consents',(select count(*) from trade_document_consent_private.consents where document_id=$2),
  'receipts',(select count(*) from trade_document_consent_private.financial_receipts where document_id=$2)) v`,[pending.parent,pending.doc]);
 const beforeCounts=await counts();
 await db.exec('begin');
 try{
  if(prepareSource)await prepareSource();
  // The calculated invoice was legitimately changed after its first attachment.
  // Refresh that attachment via its existing API and create a new consent revision;
  // never rewrite an old immutable binding to make the later approval pass.
  const customer=await q('select customer_id v from public.invoices where id=$1',[pending.parent]);
  await db.query("insert into public.trade_companies values($1,$2,$3,$4,'customer','linked')",[id(48001),A,customer,B]);
  const source=await q('select updated_at::text v from public.invoices where id=$1',[pending.parent]);
  const attachment=await q("select payload v from private.trade_document_attachments where subject_kind='invoice' and subject_id=$1",[pending.parent]);
  await q("select public.save_trade_document_attachment('invoice',$1,$2,1,$3::jsonb) v",[pending.parent,source,JSON.stringify(attachment)]);
  const payload=await q("select payload-array['company_seal_snapshot','company_seal_enabled'] v from private.trade_document_attachments where subject_kind='invoice' and subject_id=$1",[pending.parent]);
  const body={...payload,issuer_company_id:A,counterparty_company_id:B,transaction_id:pending.doc};
  const revision=await q("select trade_document_consent_private.prepare_document($1,$2,$3,1,$4::jsonb,'invoice',$5,$6,2) v",[pending.doc,A,B,JSON.stringify(body),pending.parent,source]);
  check(revision.revision,2);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
  const notice=await q('select invoice_month_close_candidate.prepare_notice($1,$2) v',[pending.parent,UA]);
  const ticket=await q('select invoice_month_close_candidate.issue_notice_ticket($1) v',[notice]);
  check(ticket.invoice_id,pending.parent);
  const expected=await q('select trade_document_consent_private.preview_confirmation($1,$2,2) v',[pending.local,A]);
  const confirm=()=>q('select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,2,$4::jsonb,$5,true,true) v',[ticket.ticket_id,pending.local,A,JSON.stringify(expected),id(49000)]);
  const used=()=>q('select consumed_at is not null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[ticket.ticket_id]);
  // The real calculator must invalidate an otherwise current notice when a
  // source day changes. Rejection must not consume the ticket or publish a seal.
  await db.exec('savepoint calculated_source_changed');
  await db.query('insert into public.attendance_entries select * from public.attendance_entries where site_id=$1',[id(40000+Number(pending.parent.slice(-4)))]);
  await c.deny(confirm,/unavailable|not_ready/);
  await db.exec('rollback to savepoint calculated_source_changed;release savepoint calculated_source_changed');
  check(await used(),false);check(await counts(),beforeCounts);
  // A failure after the actual financial approval and consent writers still
  // rolls every write back, including the durable notification consumption.
  await db.exec('savepoint calculated_late_failure');
  await db.exec("create function private.fixture_calculated_receipt_failure() returns trigger language plpgsql as $$begin raise exception 'calculated late receipt failure';end$$;create trigger fixture_calculated_receipt_failure before insert on trade_document_consent_private.financial_receipts for each row execute function private.fixture_calculated_receipt_failure()");
  await c.deny(confirm,/calculated late receipt failure/);
  await db.exec('rollback to savepoint calculated_late_failure;release savepoint calculated_late_failure');
  check(await used(),false);check(await counts(),beforeCounts);
  check(await q('select invoice_seal_frozen v from public.invoices where id=$1',[pending.parent]),false);
  check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
  const result=await confirm();
  check(result.financial_approved,true);check(result.seal_consent_recorded,true);
  check(await q('select consumed_at is not null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[ticket.ticket_id]),true);
  check(await counts(),{audit:1,consents:1,receipts:1});
  check(await q('select invoice_seal_frozen v from public.invoices where id=$1',[pending.parent]),true);
  check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 }finally{await db.exec('rollback');}
 check(await q('select to_jsonb(i) v from public.invoices i where id=$1',[pending.parent]),before);
 check(await counts(),beforeCounts);
 check(await q('select current_revision v from trade_document_consent_private.documents where id=$1',[pending.doc]),1);
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 console.log('PASS actual daily calculator -> real durable notice -> financial/seal single-transaction success and complete rollback; named adjustment scenario='+Boolean(prepareSource)+'; Auth/route/expense remain fixtures');
}
