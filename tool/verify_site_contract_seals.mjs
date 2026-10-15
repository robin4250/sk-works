// Disposable embedded PostgreSQL only. No network or app database credentials.
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const a='00000000-0000-0000-0000-000000000001';
const b='00000000-0000-0000-0000-000000000002';
const item='00000000-0000-0000-0000-000000000003';
try {
await db.exec(`create role anon; create role authenticated; create schema private; create schema auth;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create table public.companies(id uuid primary key);
create table private.site_share_inbox(data_item_id uuid primary key);
create table private.site_payment_agreement_rollout(company_id uuid,enabled boolean);
create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid);
create table private.site_payment_proposals(id uuid primary key default gen_random_uuid(),shared_item_id uuid,revision integer,terms jsonb);
create table private.site_payment_confirmations(proposal_id uuid,company_id uuid,primary key(proposal_id,company_id));
create function private.site_payment_pair(i uuid,c uuid) returns jsonb language plpgsql as $$begin
 if auth.uid() is distinct from c or c not in ('${a}','${b}') then raise exception 'forbidden' using errcode='42501';end if;
 return '{}'::jsonb;end$$;
create function private.document_company_seal_snapshot(x jsonb,c uuid,e boolean) returns jsonb language sql as $$select jsonb_build_object('company_seal_snapshot',jsonb_build_object('company_id',c,'version',1))$$;
create function private.propose_site_payment_terms(i uuid,c uuid,r integer,t jsonb) returns uuid language plpgsql as $$declare result uuid;begin
 if r<>(select coalesce(max(revision),0) from private.site_payment_proposals where shared_item_id=i) then raise exception 'stale' using errcode='40001';end if;
 insert into private.site_payment_proposals(shared_item_id,revision,terms) values(i,r+1,t) returning id into result;return result;end$$;
create function private.confirm_site_payment_terms(p uuid,c uuid) returns void language sql as $$insert into private.site_payment_confirmations values(p,c) on conflict do nothing$$;
insert into companies values('${a}'),('${b}');
insert into private.site_share_inbox values('${item}');
insert into private.document_deliveries values('${item}','${a}','${b}');
insert into private.company_data_delivery_items values('${item}','${item}');`);
await db.exec(await readFile(new URL('staged/site_contract_sealed_revision.sql',import.meta.url),'utf8'));
const terms={period_start:'2026-10-01',period_end:'2026-10-31',effective_from:'2026-10-15'};
await db.exec(`set test.actor='${a}'`);
await assert.rejects(db.query('select private.send_sealed_site_contract($1,$2,0,$3)',[item,b,terms]),/forbidden/);
await assert.rejects(db.query('select private.send_sealed_site_contract($1,$2,0,$3)',[item,a,{...terms,actor_id:b}]),/サーバー/);
const p=(await db.query('select private.send_sealed_site_contract($1,$2,0,$3) id',[item,a,terms])).rows[0].id;
await assert.rejects(db.query('select private.approve_sealed_site_contract($1,$2)',[p,a]),/受信側/);
await db.exec(`set test.actor='${b}'`);
await assert.rejects(db.query('select private.confirm_site_payment_terms($1,$2)',[p,b]),/押印承認/);
await db.query('select private.approve_sealed_site_contract($1,$2)',[p,b]);
const seals=(await db.query('select * from private.site_contract_seals order by company_id')).rows;
await db.query('select private.approve_sealed_site_contract($1,$2)',[p,b]);
assert.deepEqual((await db.query('select * from private.site_contract_seals order by company_id')).rows,seals);
assert.equal((await db.query('select count(*)::int n from private.site_contract_notification_outbox')).rows[0].n,4);
await db.exec(`set test.actor='${a}'`);
const second=(await db.query('select private.send_sealed_site_contract($1,$2,1,$3) id',[item,a,terms])).rows[0].id;
assert.equal((await db.query('select count(*)::int n from private.site_contract_seals where proposal_id=$1',[p])).rows[0].n,2);
assert.equal((await db.query('select count(*)::int n from private.site_payment_confirmations where proposal_id=$1',[p])).rows[0].n,2);
const workspace=(await db.query('select public.site_contract_workspace($1,$2) value',[item,a])).rows[0].value;
assert.equal(workspace.proposals[0].id,second);
assert.equal(workspace.proposals[0].confirmations.length,1);
assert.equal(workspace.proposals[1].seals.length,2);
assert.ok(workspace.proposals[1].seals.every(s=>s.seal_snapshot.company_id===s.company_id));
console.log('PASS actor isolation, forged actor rejection, sender/recipient boundary, immutable/idempotent seals, both-party outbox, prior agreement preservation');
} finally { await db.close(); }
