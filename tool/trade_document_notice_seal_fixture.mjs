// Existing durable notice SQL + actual financial/seal writers. Session and
// source preview/precheck/session adapters remain synthetic; guarded/readiness SQL is real.
import fs from 'node:fs/promises';
export async function verifyNoticeSeal(db,c){
 const {id,A,UA,actor,q,check,deny,prepare,preview,state}=c;
 await actor(UA);
 await db.exec(`create schema invoice_month_close_candidate;
 create table invoice_month_close_candidate.approval_permits(tx bigint,invoice_id uuid,actor_id uuid,session_id uuid,primary key(tx,invoice_id,actor_id));
 create function private.require_reauthentication_session()returns uuid language sql as $$select nullif(current_setting('test.notice_sid',true),'')::uuid$$;
 create function invoice_month_close_candidate.notification_rollout_enabled()returns boolean language sql as $$select true$$;
 alter table public.invoices add column subtotal int not null default 0;
 alter table public.invoices add column welfare_amount int not null default 0;
 create table invoice_month_close_candidate.fixture_proposals(invoice_id uuid primary key,value jsonb not null);
 create function invoice_month_close_candidate.precheck(uuid)returns text language sql as $$select case coalesce(nullif(current_setting('test.notice_ready',true),''),'ready') when 'ready' then 'source_proof_missing' else current_setting('test.notice_ready',true) end$$;
 create function invoice_month_close_candidate.approver_core_intact()returns boolean language sql as $$select true$$;
 create function invoice_month_close_candidate.notice_core_intact()returns boolean language sql as $$select true$$;
 create function invoice_month_close_candidate.preview_for_approver(uuid)returns jsonb language sql as $$select value from invoice_month_close_candidate.fixture_proposals where invoice_id=$1$$;
 create function invoice_month_close_candidate.preview_for_notice(uuid,uuid)returns jsonb language sql as $$select invoice_month_close_candidate.preview_for_approver($1)$$;
 create function invoice_month_close_candidate.revalidate_for_approver(uuid,text,text)returns void language plpgsql as $$begin
 if current_setting('test.notice_mutate_source',true)='guarded' then update public.invoices set grand_total=grand_total+1 where id=$1;end if;end$$;
 create function invoice_month_close_candidate.revalidate_for_notice(uuid,uuid,text,text)returns void language plpgsql as $$begin
 if current_setting('test.notice_mutate_source',true)='notice' then update public.invoices set grand_total=grand_total+1 where id=$1;end if;end$$;`);
 // Actual guards, including comparison after source revalidation. The proposal
 // and precheck remain explicit fixture boundaries, not real payroll sources.
 await db.exec(await fs.readFile('docs/review/invoice-month-close/guarded.sql.review-only','utf8'));
 await db.exec(await fs.readFile('docs/review/invoice-month-close/notification_readiness.sql.review-only','utf8'));
 // Real prepare/current/issue/consume functions, not caller-provided ticket rows.
 await db.exec(await fs.readFile('docs/review/invoice-month-close/notification.sql.review-only','utf8'));
 await db.exec('update invoice_month_close_candidate.notice_settings set enabled=true');
 await db.exec(await fs.readFile('docs/candidates/trade_document_notice_seal_20261028.sql.review-only','utf8'));
 const sid=id(9001);await db.query("select set_config('test.notice_sid',$1,false)",[sid]);
 const issue=async(x,session=sid)=>{
  await db.query(`insert into invoice_month_close_candidate.fixture_proposals select id,jsonb_build_object(
   'original_invoice_id',id,'calculation_blocked',false,'source_fingerprint',repeat('a',64),
   'original_invoice_fingerprint',repeat('b',64),'proposed_snapshot',snapshot-'company_seal_snapshot',
   'subtotal',subtotal,'tax',tax,'welfare',welfare_amount,'grand_total',grand_total)
   from public.invoices where id=$1 on conflict(invoice_id) do nothing`,[x.parent]);
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
 // A source revalidation that changes the saved amount must be caught by the
 // actual notification readiness/guarded comparison, rolling back all writes.
 for(const stage of ['notice','guarded']){
  await db.query("select set_config('test.notice_mutate_source',$1,false)",[stage]);
  await deny(()=>call(ticket),/unavailable|not_ready/);check(await used(ticket),false);check(await state(x),before);
 }
 await db.exec("select set_config('test.notice_mutate_source','false',false)");
 await deny(()=>call(ticket,true,false),/both explicit/);check(await used(ticket),false);check(await state(x),before);
 // The real notice_current rejects an invoice revision change even when the
 // saved source proposal remains unchanged.
 const stale=await prepare(23),staleTicket=await issue(stale);
 await db.query('update invoices set grand_total=grand_total+1 where id=$1',[stale.parent]);
 await deny(()=>call(staleTicket),/unavailable/);check(await used(staleTicket),false);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 const result=await call(ticket);check(result.financial_approved,true);check(result.seal_consent_recorded,true);check(await used(ticket),true);
 const after=await state(x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 await deny(()=>call(ticket),/unavailable/);check(await state(x),after);
 await db.exec('set role authenticated');await deny(()=>call(ticket),/permission denied/);await db.exec('reset role');
 console.log('PASS durable notice SQL + existing invoice/seal atomic composition; actual guarded/readiness SQL; source proposal/precheck/session synthetic, no public grant or product delivery');
}
