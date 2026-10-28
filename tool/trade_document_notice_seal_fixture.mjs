// Existing durable notice SQL + actual financial/seal writers. Session and
// source-readiness adapters remain synthetic: not full month-close/GoTrue proof.
import fs from 'node:fs/promises';
export async function verifyNoticeSeal(db,c){
 const {id,A,UA,actor,q,check,deny,prepare,preview,state}=c;
 await actor(UA);
 await db.exec(`create schema invoice_month_close_candidate;
 create table invoice_month_close_candidate.approval_permits(tx bigint,invoice_id uuid,actor_id uuid,session_id uuid,primary key(tx,invoice_id,actor_id));
 create function private.require_reauthentication_session()returns uuid language sql as $$select nullif(current_setting('test.notice_sid',true),'')::uuid$$;
 create function invoice_month_close_candidate.notification_rollout_enabled()returns boolean language sql as $$select true$$;
 create function invoice_month_close_candidate.guarded(uuid)returns text language sql as $$select coalesce(nullif(current_setting('test.notice_ready',true),''),'ready')$$;
 create function invoice_month_close_candidate.notification_readiness(p_invoice uuid,p_actor uuid)returns jsonb language sql as $$
 select jsonb_build_object('status',coalesce(nullif(current_setting('test.notice_ready',true),''),'ready'),
 'invoice_revision',i.updated_at::text,'source_fingerprint',repeat('a',64)) from public.invoices i where id=p_invoice$$;`);
 // Real prepare/current/issue/consume functions, not caller-provided ticket rows.
 await db.exec(await fs.readFile('docs/review/invoice-month-close/notification.sql.review-only','utf8'));
 await db.exec('update invoice_month_close_candidate.notice_settings set enabled=true');
 await db.exec(await fs.readFile('docs/candidates/trade_document_notice_seal_20261028.sql.review-only','utf8'));
 const sid=id(9001);await db.query("select set_config('test.notice_sid',$1,false)",[sid]);
 const issue=async(x,session=sid)=>{
  const notice=await q('select invoice_month_close_candidate.prepare_notice($1,$2) v',[x.parent,UA]);
  await db.query("select set_config('test.notice_sid',$1,false)",[session]);
  const ticket=await q('select invoice_month_close_candidate.issue_notice_ticket($1) v',[notice]);
  await db.query("select set_config('test.notice_sid',$1,false)",[sid]);return ticket.ticket_id;
 };
 const x=await prepare(21),p=await preview(x),before=await state(x),ticket=await issue(x);
 const call=(t,financial=true,seal=true)=>q('select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,1,$4::jsonb,$5,$6,$7) v',[t,x.local,A,JSON.stringify(p),id(29000),financial,seal]);
 const used=t=>q('select consumed_at is not null v from invoice_month_close_candidate.notice_open_tickets where id=$1',[t]);
 await deny(()=>call(ticket),/disabled/);check(await used(ticket),false);check(await state(x),before);
 await db.exec('update trade_document_consent_private.notice_confirmation_settings set enabled=true');
 const wrong=await issue(await prepare(22));await deny(()=>call(wrong),/parent mismatch/);check(await used(wrong),false);check(await state(x),before);
 const foreign=await issue(x,id(9002));await deny(()=>call(foreign),/unavailable/);check(await used(foreign),false);
 await db.exec("select set_config('test.notice_ready','data_changed',false)");await deny(()=>call(ticket),/unavailable|not_ready/);check(await used(ticket),false);check(await state(x),before);
 await db.exec("select set_config('test.notice_ready','ready',false)");
 await deny(()=>call(ticket,true,false),/both explicit/);check(await used(ticket),false);check(await state(x),before);
 // The real notice_current rejects an invoice revision change even when the
 // synthetic readiness adapter still reports ready.
 const stale=await prepare(23),staleTicket=await issue(stale);
 await db.query('update invoices set grand_total=grand_total+1 where id=$1',[stale.parent]);
 await deny(()=>call(staleTicket),/unavailable/);check(await used(staleTicket),false);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 const result=await call(ticket);check(result.financial_approved,true);check(result.seal_consent_recorded,true);check(await used(ticket),true);
 const after=await state(x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 await deny(()=>call(ticket),/unavailable/);check(await state(x),after);
 await db.exec('set role authenticated');await deny(()=>call(ticket),/permission denied/);await db.exec('reset role');
 console.log('PASS durable notice SQL + existing invoice/seal atomic composition; source readiness/session synthetic, no public grant or product delivery');
}
