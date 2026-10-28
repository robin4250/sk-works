// Synthetic notice/session/readiness adapters; actual existing financial/seal
// writers are supplied by the parent fixture. Not full month-close integration.
import fs from 'node:fs/promises';
export async function verifyNoticeSeal(db,c){
 const {id,A,UA,actor,q,check,deny,prepare,preview,state}=c;
 await actor(UA);
 await db.exec(`create schema invoice_month_close_candidate;
 create table invoice_month_close_candidate.fixture_tickets(id uuid primary key,invoice_id uuid,actor_id uuid,session_id uuid,consumed boolean default false);
 create table invoice_month_close_candidate.approval_permits(tx bigint,invoice_id uuid,actor_id uuid,session_id uuid,primary key(tx,invoice_id,actor_id));
 create function private.require_reauthentication_session()returns uuid language sql as $$select nullif(current_setting('test.notice_sid',true),'')::uuid$$;
 create function invoice_month_close_candidate.notification_rollout_enabled()returns boolean language sql as $$select true$$;
 create function invoice_month_close_candidate.guarded(uuid)returns text language sql as $$select coalesce(nullif(current_setting('test.notice_ready',true),''),'ready')$$;
 create function invoice_month_close_candidate.consume_notice_ticket(p_ticket uuid)returns uuid language plpgsql as $$
 declare invoice uuid;begin
 update invoice_month_close_candidate.fixture_tickets set consumed=true where id=p_ticket and consumed=false and actor_id=auth.uid() and session_id=private.require_reauthentication_session() returning invoice_id into invoice;
 if invoice is null then raise exception 'notice_unavailable';end if;return invoice;end $$;`);
 await db.exec(await fs.readFile('docs/candidates/trade_document_notice_seal_20261028.sql.review-only','utf8'));
 const sid=id(9001);await db.query("select set_config('test.notice_sid',$1,false)",[sid]);
 const x=await prepare(21),p=await preview(x),before=await state(x),ticket=id(9021);
 const add=async(t,parent,session=sid)=>db.query('insert into invoice_month_close_candidate.fixture_tickets(id,invoice_id,actor_id,session_id)values($1,$2,$3,$4)',[t,parent,UA,session]);
 const call=(t,financial=true,seal=true)=>q('select trade_document_consent_private.confirm_invoice_from_notice($1,$2,$3,1,$4::jsonb,$5,$6,$7) v',[t,x.local,A,JSON.stringify(p),id(9100),financial,seal]);
 const used=t=>q('select consumed v from invoice_month_close_candidate.fixture_tickets where id=$1',[t]);
 await add(ticket,x.parent);
 await deny(()=>call(ticket),/disabled/);check(await used(ticket),false);check(await state(x),before);
 await db.exec('update trade_document_consent_private.notice_confirmation_settings set enabled=true');
 const wrong=id(9022);await add(wrong,id(9999));await deny(()=>call(wrong),/parent mismatch/);check(await used(wrong),false);check(await state(x),before);
 const foreign=id(9023);await add(foreign,x.parent,id(9002));await deny(()=>call(foreign),/unavailable/);check(await used(foreign),false);
 await db.exec("select set_config('test.notice_ready','data_changed',false)");await deny(()=>call(ticket),/not_ready/);check(await used(ticket),false);check(await state(x),before);
 await db.exec("select set_config('test.notice_ready','ready',false)");
 await deny(()=>call(ticket,true,false),/both explicit/);check(await used(ticket),false);check(await state(x),before);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 const result=await call(ticket);check(result.financial_approved,true);check(result.seal_consent_recorded,true);check(await used(ticket),true);
 const after=await state(x);check(after.audit,1);check(after.consents,1);check(after.receipts,1);
 check(await q('select count(*)::int v from invoice_month_close_candidate.approval_permits'),0);
 await deny(()=>call(ticket),/unavailable/);check(await state(x),after);
 await db.exec('set role authenticated');await deny(()=>call(ticket),/permission denied/);await db.exec('reset role');
 console.log('PASS notice + existing invoice/seal atomic composition; synthetic notice/session/readiness only, no public grant or product delivery');
}
