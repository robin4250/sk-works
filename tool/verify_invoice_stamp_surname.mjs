// Isolated synthetic PGlite only; no production connection.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const uid=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const cid='10000000-0000-0000-0000-000000000001';
const iid='20000000-0000-0000-0000-000000000001';
const rpc=(name,args=[])=>db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) value`,args);
const actor=n=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid(n)]);
try {
 for(const p of ['supabase/tests/invoice_stamp_approval_workflow.sql','supabase/migrations/20261005081500_invoice_approval_workflow.sql','supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql','supabase/migrations/20261009010422_invoice_explicit_stamp_surname_snapshot.sql']) await db.exec(read(p));
 await actor(1);
 await db.exec(`insert into invoices(id,company_id,billing_period_start,billing_period_end,status,grand_total) values('${iid}','${cid}','2026-10-01','2026-10-31','draft',100)`);
 await db.exec(`select private.ensure_invoice_approval_rows('${iid}')`);
 await db.exec(`insert into user_profiles values('${uid(1)}','斉藤隆一')`);
 assert.equal((await rpc('invoice_stamp_surname_rows',[iid])).rows[0].value.enabled,false);
 await assert.rejects(rpc('set_invoice_stamp_surname',[iid,'斉藤']),/unavailable/);
 await db.exec(`insert into private.invoice_stamp_surname_rollout values('${cid}',true)`);
 await assert.rejects(rpc('approve_invoice_with_stamp_surname',[iid]),/explicit surname/);
 for(const bad of ['', ' '.repeat(3),'x'.repeat(31),'姓\n名']) await assert.rejects(rpc('set_invoice_stamp_surname',[iid,bad]),/explicit surname/);
 await actor(2);
 await assert.rejects(rpc('set_invoice_stamp_surname',[iid,'他人']),/own approval/);
 await actor(4);
 await assert.rejects(rpc('invoice_stamp_surname_rows',[iid]),/invoice not found/);
 await actor(1);
 await rpc('set_invoice_stamp_surname',[iid,'斉藤']);
 assert.equal((await rpc('invoice_stamp_surname_rows',[iid])).rows[0].value.names[0].draft_surname,'斉藤');
 assert.equal((await rpc('approve_invoice_with_stamp_surname',[iid])).rows[0].value,true);
 const stamp=(await db.query('select * from private.invoice_stamp_surname_snapshots')).rows[0];
 assert.equal(stamp.surname,'斉藤');
 await rpc('approve_invoice_with_stamp_surname',[iid]);
 assert.equal((await db.query('select count(*)::int n from private.invoice_stamp_surname_snapshots')).rows[0].n,1);
 await assert.rejects(rpc('set_invoice_stamp_surname',[iid,'変名']),/pending own/);
 await db.exec("update user_profiles set display_name='新姓名'");
 assert.equal((await rpc('invoice_stamp_surname_rows',[iid])).rows[0].value.names[0].snapshot_surname,'斉藤');
 await db.exec('update private.invoice_stamp_surname_rollout set enabled=false');
 assert.equal((await rpc('invoice_stamp_surname_rows',[iid])).rows[0].value.names[0].snapshot_surname,'斉藤');
 await assert.rejects(rpc('approve_invoice_with_stamp_surname',[iid]),/unavailable/);
 await db.exec('update private.invoice_stamp_surname_rollout set enabled=true');
 await rpc('cancel_invoice_approval',[iid]);
 await rpc('set_invoice_stamp_surname',[iid,'斎藤']);
 await rpc('approve_invoice_with_stamp_surname',[iid]);
 assert.equal((await db.query('select count(*)::int n from private.invoice_stamp_surname_snapshots')).rows[0].n,2);
 assert.equal((await rpc('invoice_stamp_surname_rows',[iid])).rows[0].value.names[0].snapshot_surname,'斎藤');
 assert.equal((await db.query('select surname from private.invoice_stamp_surname_snapshots where approved_at=$1',[stamp.approved_at])).rows[0].surname,'斉藤');
 const oldIid='20000000-0000-0000-0000-000000000002';
 await db.exec(`insert into invoices(id,company_id,billing_period_start,billing_period_end,status,grand_total) values('${oldIid}','${cid}','2026-09-01','2026-09-30','draft',100)`);
 await rpc('approve_invoice',[oldIid]);
 assert.equal((await rpc('invoice_stamp_surname_rows',[oldIid])).rows[0].value.names[0].snapshot_surname,null);
 assert.equal((await db.query('select count(*)::int n from private.invoice_stamp_surname_snapshots where invoice_id=$1',[oldIid])).rows[0].n,0);
 await db.exec(`delete from company_members where company_id='${cid}' and user_id='${uid(1)}'`);
 await assert.rejects(rpc('invoice_stamp_surname_rows',[iid]),/invoice not found/);
 await db.exec(`insert into company_members values('${cid}','${uid(1)}','owner')`);
 for(const table of ['invoice_stamp_surname_rollout','invoice_stamp_surname_drafts','invoice_stamp_surname_snapshots','invoice_stamp_surname_history']) {
  for(const privilege of ['SELECT','INSERT','UPDATE','DELETE']) {
   assert.equal((await db.query(`select has_table_privilege('authenticated','private.${table}','${privilege}') ok`)).rows[0].ok,false);
  }
 }
 await db.exec('set role authenticated');
 await assert.rejects(db.query('select * from private.invoice_stamp_surname_snapshots'),/permission denied/);
 await db.exec('reset role');
 assert.equal((await db.query("select has_function_privilege('anon','public.set_invoice_stamp_surname(uuid,text)','execute') ok")).rows[0].ok,false);
 assert.equal((await db.query("select count(*)::int n from public.invoice_approval_audit where action='approved' and invoice_id=$1",[iid])).rows[0].n,2);
 console.log('PASS: OFF, exact company, own pending only, explicit name, immutable snapshot, retry, profile change, cancel/reapprove history and ACL');
} finally {await db.close();}
