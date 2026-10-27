import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(process.env.SKO_ADJUSTMENT_ROOT||'../doc-adjustment-buttons-candidate');
const originalPath=resolve(root,'tool/verify_adjustment_real_refresh.mjs');
const original=await readFile(originalPath,'utf8');
const candidate=await readFile(resolve(process.env.SKO_PREVIEW_SQL||'../invoice-correction-preview-candidate/preview.sql.review-only'),'utf8');
const marker='let checks=0;';assert.equal(original.split(marker).length,2);
const payload=`
// Only isolated, synthetic fixture data. Preserve the invoice/approval record.
await db.exec("create or replace function private.has_company_feature(p_company uuid,p_feature text) returns boolean language sql as $$select true$$;");
await db.exec("create or replace function private.account_access_allowed() returns boolean language sql as $$select true$$;");
await db.exec(${JSON.stringify(candidate)});
await db.exec("create table if not exists private.route_journey_captures(id uuid,company_id uuid); create table if not exists private.route_journey_visit_events(capture_id uuid); create table if not exists public.invoice_approval_audit(invoice_id uuid,company_id uuid); create table if not exists public.daily_reports(id uuid,company_id uuid); create table if not exists public.daily_report_workers(report_id uuid); create table if not exists public.route_stops(company_id uuid); create table if not exists private.route_billing_quantity_requests(id uuid,company_id uuid); create table if not exists private.route_billing_quantity_evidence(request_id uuid); create table if not exists private.expense_amount_consumptions(company_id uuid);");
await db.query("update site_financial_settings set billing_allowance_1_name='合成手当',billing_allowance_1_amount_yen=10,billing_overtime_hour_rate_yen=20 where company_id=$1 and site_id=$2",[company,site]);

// Existing approved route allocation, accepted extra expense and one adjustment
// are present before both original and corrected views are built.
const routeSite=id(104),routeReport=id(105),routeStart=id(106),routeCap1=id(107),routeCap2=id(108),expenseId=id(109);
await db.query("update attendance_entries set work_date='2026-10-16',work_category=null where company_id=$1 and site_id=$2 and work_date='2026-10-01'",[company,site]);
await db.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-22','day',1),($1,$2,$3,'2026-10-24','day',1),($1,$2,$3,'2026-10-26','day',1)",[company,site,worker]);

await db.query("insert into sites(id,company_id,customer_id,name) values($1,$2,$3,'合成ルート現場')",[routeSite,company,customer]);
await db.query('insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,150,5)',[company,routeSite]);
await db.query("insert into private.route_visit_reports(id,company_id,created_by,report_date,status,workers,roster_workers,site_id,site_name,source_clock_in_id,start_capture_id,end_capture_id) values($1,$2,$3,'2026-10-12','completed',$4::jsonb,$4::jsonb,$5,'合成ルート現場',$6,$7,$8)",[routeReport,company,actor,JSON.stringify([{worker_id:worker,worker_name:'合成社員'}]),routeSite,routeStart,routeCap1,routeCap2]);
const routeRows=(await db.query('select public.submit_route_customer_day_allocations($1,$2::uuid[],$3::jsonb) v',[worker,[routeReport],JSON.stringify([{customer_id:customer,quantity:1}])])).rows[0].v;
await db.query("select public.decide_route_billing_quantity($1,1,'approve','',1,$2,150)",[routeRows[0].id,routeSite]);
await db.query("insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision) values($1,$2,$3,'合成社員',$4,'2026-10-01','合成経費',4,'approved','customer',$5,2)",[expenseId,company,worker,actor,customer]);
await db.query("insert into private.expense_settlement_choices(claim_id,company_id,method,settlement_month,revision,chosen_by,approval_current,cost_allocation_current) values($1,$2,'cash','2026-10-01',2,$3,true,true)",[expenseId,company,actor]);
const adjustmentCommand={command_id:crypto.randomUUID(),company_id:company,kind:'invoice',party_id:customer,month:'2026-10-01',expected_version:0,action:'add',entry_id:null,sign:'plus',title:'合成追加',amount_yen:10,recurrence:'once',effective_month:'2026-10-01',calculation_mode:'settlement_yen',site_id:null,expected_template_version:null,update_scope:'current_month'};
const adjustmentPreview=(await db.query('select public.preview_trade_document_adjustment($1) v',[JSON.stringify(adjustmentCommand)])).rows[0].v;
await db.query('select public.apply_trade_document_adjustment($1,$2) v',[JSON.stringify(adjustmentCommand),adjustmentPreview.token]);
await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
const addExtras=()=>db.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours,allowance_names) values($1,$2,$3,'2026-10-25','day',1,0,0,ARRAY['合成手当']),($1,$2,$3,'2026-10-27','day',1,1,0,ARRAY['合成手当'])",[company,site,worker]);
await addExtras();await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
const expected=(await db.query('select snapshot,subtotal,tax,welfare_amount,grand_total from invoices where company_id=$1 and customer_id=$2',[company,customer])).rows[0];
await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date in ('2026-10-25','2026-10-27')",[company,site]);
await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
await db.query("update invoices set status='finalized',finalized_at=now() where company_id=$1 and customer_id=$2",[company,customer]);
await db.query("update invoices set status='draft',finalized_at=null where company_id=$1 and customer_id=$2",[company,customer]);
const frozen=(await db.query('select * from invoices where company_id=$1 and customer_id=$2',[company,customer])).rows[0];assert.equal(frozen.invoice_seal_frozen,true);
await addExtras();await db.query('select private.refresh_automatic_invoice($1,$2,$3)',[company,customer,'2026-10-01']);
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
const correctionPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
assert.match(correctionPreview.source_fingerprint,/^[0-9a-f]{64}$/);assert.match(correctionPreview.original_invoice_fingerprint,/^[0-9a-f]{64}$/);
const unchangedPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.equal(unchangedPreview.source_fingerprint,correctionPreview.source_fingerprint);
await db.exec("create or replace function private.account_access_allowed() returns boolean language sql as $$select false$$;");
const authDrift=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.notEqual(authDrift.source_fingerprint,correctionPreview.source_fingerprint);
await db.exec("create or replace function private.account_access_allowed() returns boolean language sql as $$select true$$;");
await db.query("update private.route_visit_reports set site_name='合成変更' where id=$1",[routeReport]);
const routeChanged=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.notEqual(routeChanged.source_fingerprint,correctionPreview.source_fingerprint);
await db.query("update private.route_visit_reports set site_name='合成ルート現場' where id=$1",[routeReport]);
await db.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
const changedPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;assert.notEqual(changedPreview.source_fingerprint,correctionPreview.source_fingerprint);
await db.query("update attendance_entries set overtime_hours=1 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
assert.ok(expected.snapshot.sites.some(item=>item.route_billing_request_id));assert.equal(expected.snapshot.expense_extra_amount_yen,4);assert.equal(expected.snapshot.document_adjustments_v1.length,1);assert.equal(Object.hasOwn(correctionPreview.proposed_snapshot,'company_seal_snapshot'),false);
await db.query("update company_members set role='worker' where company_id=$1 and user_id=$2",[company,actor]);await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_not_allowed/);await db.query("update company_members set role='admin' where company_id=$1 and user_id=$2",[company,actor]);
const oldSite=frozen.snapshot.sites.find(item=>item.site_id===site);const newSite=correctionPreview.proposed_snapshot.sites.find(item=>item.site_id===site);
assert.equal(Number(oldSite.lines[0].quantity),4);assert.equal(Number(newSite.lines[0].quantity),6);
assert.equal(Number(frozen.snapshot.sites.find(item=>item.route_billing_request_id).lines[0].quantity),1);assert.equal(Number(correctionPreview.proposed_snapshot.sites.find(item=>item.route_billing_request_id).lines[0].quantity),1);
const expectedSnapshot={...expected.snapshot};delete expectedSnapshot.company_seal_snapshot;
assert.deepEqual(correctionPreview.proposed_snapshot,expectedSnapshot);assert.equal(correctionPreview.subtotal,expected.subtotal);assert.equal(correctionPreview.tax,expected.tax);assert.equal(correctionPreview.welfare,expected.welfare_amount);assert.equal(correctionPreview.grand_total,expected.grand_total);
assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);

// The two-session checks run only against the explicitly isolated native PG17 fixture.
if(process.env.SKO_DOCUMENT_ADJUSTMENT_FIXTURE_URL){
 const {connectFixture}=await import(process.argv[2]);const writer=await connectFixture();
 const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
 const readLocked=async()=>(await db.query('select invoice_correction_preview_private.locked_preview($1) v',[frozen.id])).rows[0].v;
 try {
  await writer.query('begin');
  await writer.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
  let pending=readLocked();await pause(200);await writer.query('commit');
  let result=await pending;assert.notEqual(result.source_fingerprint,correctionPreview.source_fingerprint);
  let resultSite=result.proposed_snapshot.sites.find(item=>item.site_id===site);
  assert.notDeepEqual(resultSite,newSite);
  await db.query("update attendance_entries set overtime_hours=1 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
  await writer.query('begin');
  await writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]);
  pending=readLocked();await pause(200);await writer.query('commit');result=await pending;
  resultSite=result.proposed_snapshot.sites.find(item=>item.site_id===site);assert.equal(Number(resultSite.lines[0].quantity),7);
  assert.notEqual(result.source_fingerprint,correctionPreview.source_fingerprint);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  await db.query('begin');result=await readLocked();
  let finished=false;
  pending=writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]).then(()=>{finished=true;});
  await pause(200);assert.equal(finished,false);await db.query('commit');await pending;assert.equal(finished,true);
  const afterInsert=await readLocked();assert.notEqual(afterInsert.source_fingerprint,result.source_fingerprint);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  // A company-scoped advisory lock and locks on existing rows cannot protect a missing row
  // when a legacy writer does not acquire the same advisory lock.
  await db.query('begin');await db.query('select pg_advisory_xact_lock($1)',[618273]);
  await db.query('select 1 from attendance_entries where company_id=$1 and site_id=$2 for share',[company,site]);
  const scopedBefore=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  await writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]);
  await writer.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(998)]);
  await db.query('commit');
  const scopedAfter=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  assert.notEqual(scopedBefore.source_fingerprint,scopedAfter.source_fingerprint);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  await writer.query('delete from companies where id=$1',[id(998)]);
  console.log(JSON.stringify({nonparticipant_insert_bypasses_scoped_lock:true,unrelated_company_write_allowed:true}));
  // Experimental fixture-only writer barrier: plain legacy INSERT/UPDATE participates through
  // a trigger; a different company's write must remain independent. Not production migration.
  await db.exec("create function private.synthetic_company_writer_lock() returns trigger language plpgsql as $$begin perform pg_advisory_xact_lock(hashtextextended('invoice-fixture:'||coalesce(new.company_id,old.company_id)::text,0));return coalesce(new,old);end$$; create trigger synthetic_writer_barrier before insert or update or delete on public.attendance_entries for each row execute function private.synthetic_company_writer_lock();");
  await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture:'||$1::text,0))",[company]);
  const beforeBarrier=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  let barrierDone=false;const barrierInsert=writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]).then(()=>{barrierDone=true;});
  await pause(200);assert.equal(barrierDone,false);
  // The locked transaction does not block another company's independent lock.
  const {connectFixture:anotherConnect}=await import(process.argv[2]);const other=await anotherConnect();
  try{await other.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture:'||$1::text,0))",[id(998)]);}finally{await other.end();}
  await db.query('commit');await barrierInsert;assert.equal(barrierDone,true);
  const afterBarrier=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  assert.notEqual(afterBarrier.source_fingerprint,beforeBarrier.source_fingerprint);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture:'||$1::text,0))",[company]);
  let updateDone=false;const barrierUpdate=writer.query("update attendance_entries set overtime_hours=2 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]).then(()=>{updateDone=true;});
  await pause(200);assert.equal(updateDone,false);await db.query('commit');await barrierUpdate;assert.equal(updateDone,true);
  await db.query("update attendance_entries set overtime_hours=1 where company_id=$1 and site_id=$2 and work_date='2026-10-27'",[company,site]);
  console.log(JSON.stringify({fixture_legacy_update_waits_company_lock:true}));
  await db.exec('drop trigger synthetic_writer_barrier on public.attendance_entries;drop function private.synthetic_company_writer_lock();');
  console.log(JSON.stringify({fixture_legacy_insert_waits_company_lock:true,other_company_lock_independent:true,scope_limited_to_one_fixture_table:true}));
  // Synthetic integration only: exercise existing fixture triggers and company-key changes.
  // Joined-child tables and all production deployment effects remain unverified.
  await db.exec("create function private.synthetic_company_barrier_v2() returns trigger language plpgsql as $$declare v uuid;begin for v in select distinct c from (values (case when TG_OP <> 'INSERT' then old.company_id end),(case when TG_OP <> 'DELETE' then new.company_id end)) s(c) where c is not null order by c loop perform pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||v::text,0));end loop;if TG_OP='DELETE' then return old;end if;return new;end$$;");
  const protectedTables=['public.attendance_entries','public.site_financial_settings','private.route_billing_quantity_requests','private.expense_claims','document_adjustment_private.rollout'];
  for(const table of protectedTables)await db.exec('create trigger synthetic_barrier_v2 before insert or update or delete on '+table+' for each row execute function private.synthetic_company_barrier_v2()');
  for(const table of protectedTables){
   await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[company]);
   await writer.query('begin');let finished=false;
   const q=writer.query('update '+table+' set company_id=company_id where company_id=$1',[company]).then(()=>{finished=true;});
   await pause(200);assert.equal(finished,false,'writer did not wait for '+table);await db.query('commit');await q;await writer.query('rollback');
  }
  let deleteRejected=0;
  for(const table of protectedTables){
   for(const verb of ['insert','delete']){
    await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[company]);
    await writer.query('begin');let finished=false;
    const sql=verb==='insert'?'insert into '+table+' select * from '+table+' where company_id=$1 on conflict do nothing':'delete from '+table+' where company_id=$1';
    const pendingWrite=writer.query(sql,[company]).then(()=>{finished=true;return true;},()=>{finished=true;return false;});
    await pause(200);assert.equal(finished,false,verb+' did not wait for '+table);
    await db.query('commit');const ok=await pendingWrite;if(!ok){if(verb==='insert')throw Error('fixture insert rejected on '+table);deleteRejected++;}
    await writer.query('rollback');
   }
  }
  console.log(JSON.stringify({fixture_five_table_insert_delete_wait:true,fixture_delete_constraint_rejections:deleteRejected}));
  // Actual new rows (not ON CONFLICT): each legacy insert is rolled back after verifying
  // it waited, preserving the fixture; route submission's existing audit trigger runs.
  await db.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(996)]);
  await db.query("insert into sites(id,company_id,customer_id,name) values($1,$2,$3,'合成新現場')",[id(995),company,customer]);
  await writer.query("select set_config('test.uid',$1,false)",[actor]);
  const newInserts=[
   {sql:"insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-29','day',1)",args:[company,site,worker],lock:company},
   {sql:'insert into site_financial_settings(company_id,site_id,billing_unit_price_yen,welfare_rate) values($1,$2,200,5)',args:[company,id(995)],lock:company},
   {sql:"insert into private.route_billing_quantity_requests(id,company_id,worker_id,worker_name,work_date,customer_id,customer_name,requested_quantity,quantity,status,requested_by) values($1,$2,$3,'合成作業者','2026-10-29',$4,'合成取引先',1,1,'pending',$5)",args:[id(994),company,worker,customer,actor],lock:company},
   {sql:"insert into private.expense_claims(id,company_id,applicant_id,applicant_name,created_by,incurred_on,description,amount_yen,approval,allocation,counterparty_id,revision) values($1,$2,$3,'合成作業者',$4,'2026-10-29','合成経費',4,'approved','customer',$5,2)",args:[id(993),company,worker,actor,customer],lock:company},
   {sql:'insert into document_adjustment_private.rollout(company_id,enabled) values($1,true)',args:[id(996)],lock:id(996)}
  ];
  for(const c of newInserts){
   await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[c.lock]);
   await writer.query('begin');let done=false;
   const insert=writer.query(c.sql,c.args).then(result=>{done=true;return result;});
   await pause(200);assert.equal(done,false);await db.query('commit');const inserted=await insert;assert.equal(inserted.rowCount,1);if(c.args[0]===id(994)){const audits=await writer.query('select count(*)::int n from private.route_billing_quantity_audit where request_id=$1',[id(994)]);assert.equal(audits.rows[0].n,1);}await writer.query('rollback');
  }
  await db.query('delete from sites where id=$1',[id(995)]);await db.query('delete from companies where id=$1',[id(996)]);
  console.log(JSON.stringify({five_distinct_fixture_inserts_wait_and_succeed:true,rolled_back:true,route_audit_trigger_preserved:true}));
  // Join-owned child tables have no company_id; fixture-only barrier derives it from parent.
  // Parent moves/deletes and absent-parent races are not covered by this experiment.
  await db.exec("create function private.synthetic_child_barrier() returns trigger language plpgsql as $$declare r jsonb;c uuid;i integer;companies uuid[]:='{}';begin for r in select j from (values(case when TG_OP<>'INSERT' then to_jsonb(old) end),(case when TG_OP<>'DELETE' then to_jsonb(new) end)) x(j) where j is not null loop if TG_TABLE_NAME='route_billing_quantity_evidence' then select company_id into c from private.route_billing_quantity_requests where id=(r->>'request_id')::uuid;else select company_id into c from public.daily_reports where id=(r->>'report_id')::uuid;end if;if c is null then raise exception 'synthetic_parent_missing';end if;companies:=array_append(companies,c);end loop;for c in select distinct unnest(companies) order by 1 loop perform pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||c::text,0));end loop;i:=0;for r in select j from (values(case when TG_OP<>'INSERT' then to_jsonb(old) end),(case when TG_OP<>'DELETE' then to_jsonb(new) end)) x(j) where j is not null loop i:=i+1;if TG_TABLE_NAME='route_billing_quantity_evidence' then select company_id into c from private.route_billing_quantity_requests where id=(r->>'request_id')::uuid;else select company_id into c from public.daily_reports where id=(r->>'report_id')::uuid;end if;if c is distinct from companies[i] then raise exception 'synthetic_parent_moved';end if;end loop;if TG_OP='DELETE' then return old;end if;return new;end$$;create trigger synthetic_child_barrier before insert or update or delete on private.route_billing_quantity_evidence for each row execute function private.synthetic_child_barrier();create trigger synthetic_child_barrier before insert or update or delete on public.daily_report_workers for each row execute function private.synthetic_child_barrier();");
  await db.query('insert into public.daily_reports(id,company_id) values($1,$2)',[id(992),company]);
  const childInserts=[
   {sql:"insert into private.route_billing_quantity_evidence(request_id,report_id,source_clock_in_id,start_capture_id,end_capture_id,site_id,site_name,customer_id) values($1,$2,$3,$4,$5,$6,'合成現場',$7)",args:[routeRows[0].id,id(991),id(990),id(989),id(988),site,customer]},
   {sql:'insert into public.daily_report_workers(report_id) values($1)',args:[id(992)]}
  ];
  for(const c of childInserts){
   await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[company]);
   await writer.query('begin');let done=false;const pending=writer.query(c.sql,c.args).then(v=>{done=true;return v;});
   await pause(200);assert.equal(done,false);await db.query('commit');const inserted=await pending;assert.equal(inserted.rowCount,1);await writer.query('rollback');
  }
  await db.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(987)]);
  await db.query('insert into public.daily_reports(id,company_id) values($1,$2)',[id(986),id(987)]);
  await db.query('insert into public.daily_report_workers(report_id) values($1)',[id(992)]);
  for(const lockCompany of [company,id(987)]){
   await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[lockCompany]);
   await writer.query('begin');let done=false;const move=writer.query('update public.daily_report_workers set report_id=$1 where report_id=$2',[id(986),id(992)]).then(()=>{done=true;});
   await pause(200);assert.equal(done,false);await db.query('commit');await move;await writer.query('rollback');
  }
  await db.query('delete from public.daily_report_workers where report_id=$1',[id(992)]);
  await db.query('delete from public.daily_reports where id=$1',[id(986)]);await db.query('delete from companies where id=$1',[id(987)]);
  console.log(JSON.stringify({fixture_child_move_old_and_new_lock:true,parent_concurrent_move_unverified:true}));
  // A parent moved/deleted while child waits must be detected after the lock wait.
  await db.exec('create trigger synthetic_parent_barrier before insert or update or delete on public.daily_reports for each row execute function private.synthetic_company_barrier_v2()');
  await db.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(985)]);
  await db.query('insert into public.daily_reports(id,company_id) values($1,$2)',[id(984),company]);
  await db.query('begin');await db.query('update public.daily_reports set company_id=$1 where id=$2',[id(985),id(984)]);
  await writer.query('begin');let childDone=false;
  let pendingChild=writer.query('insert into public.daily_report_workers(report_id) values($1)',[id(984)]).then(()=>{childDone=true;return null;},e=>{childDone=true;return e;});
  await pause(200);assert.equal(childDone,false);await db.query('commit');let rejectedChild=await pendingChild;assert.match(rejectedChild?.message||'',/synthetic_parent_moved/);await writer.query('rollback');
  await db.query('update public.daily_reports set company_id=$1 where id=$2',[company,id(984)]);
  await db.query('begin');await db.query('delete from public.daily_reports where id=$1',[id(984)]);
  await writer.query('begin');childDone=false;pendingChild=writer.query('insert into public.daily_report_workers(report_id) values($1)',[id(984)]).then(()=>{childDone=true;return null;},e=>{childDone=true;return e;});
  await pause(200);assert.equal(childDone,false);await db.query('commit');rejectedChild=await pendingChild;assert.match(rejectedChild?.message||'',/synthetic_parent_moved/);await writer.query('rollback');
  // REPEATABLE READ keeps the old parent snapshot after waiting. Demonstrate why
  // this READ COMMITTED-only fixture barrier cannot be used indiscriminately.
  await db.query('insert into public.daily_reports(id,company_id) values($1,$2)',[id(984),company]);
  await db.query('begin');await db.query('update public.daily_reports set company_id=$1 where id=$2',[id(985),id(984)]);
  await writer.query('begin isolation level repeatable read');await writer.query('select company_id from public.daily_reports where id=$1',[id(984)]);
  childDone=false;pendingChild=writer.query('insert into public.daily_report_workers(report_id) values($1)',[id(984)]).then(v=>{childDone=true;return v;},e=>{childDone=true;throw e;});
  await pause(200);assert.equal(childDone,false);await db.query('commit');const staleInsert=await pendingChild;assert.equal(staleInsert.rowCount,1);await writer.query('rollback');
  await db.query('delete from public.daily_reports where id=$1',[id(984)]);
  console.log(JSON.stringify({repeatable_read_stale_parent_reproduced:true,barrier_not_safe_for_all_isolation_levels:true}));
  await db.query('delete from companies where id=$1',[id(985)]);await db.exec('drop trigger synthetic_parent_barrier on public.daily_reports');
  console.log(JSON.stringify({fixture_parent_move_and_delete_fail_closed:true}));
  await db.query('delete from public.daily_reports where id=$1',[id(992)]);
  await db.exec('drop trigger synthetic_child_barrier on private.route_billing_quantity_evidence;drop trigger synthetic_child_barrier on public.daily_report_workers;drop function private.synthetic_child_barrier();');
  console.log(JSON.stringify({fixture_two_joined_child_inserts_wait:true,parent_move_delete_unverified:true}));
  // A legacy update moving a row into a second company must acquire both company keys.
  await db.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(997)]);
  await db.query('begin');await db.query("select pg_advisory_xact_lock(hashtextextended('invoice-fixture-v2:'||$1::text,0))",[id(997)]);
  await writer.query('begin');let moveFinished=false;
  const move=writer.query("update attendance_entries set company_id=$1 where company_id=$2 and site_id=$3 and work_date='2026-10-27'",[id(997),company,site]).then(()=>{moveFinished=true;});
  await pause(200);assert.equal(moveFinished,false);await db.query('commit');await move;await writer.query('rollback');
  await db.query('delete from companies where id=$1',[id(997)]);
  for(const table of protectedTables)await db.exec('drop trigger synthetic_barrier_v2 on '+table);
  await db.exec('drop function private.synthetic_company_barrier_v2()');
  console.log(JSON.stringify({fixture_existing_writer_updates_wait:true,fixture_five_real_tables:true,company_move_checks_old_and_new:true,joined_children_not_covered:true}));
  // SERIALIZABLE can commit before a non-participating writer in serialization order.
  // Stage therefore becomes stale after commit; a later publish must revalidate.
  await db.query('begin isolation level serializable');
  const serialPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  await writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]);
  await db.query('commit');
  const serialAfter=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  assert.notEqual(serialPreview.source_fingerprint,serialAfter.source_fingerprint);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  // A short final gate checks the staged data before any publish operation.
  await db.query('begin');const gateStart=Date.now();
  await db.query('select invoice_correction_preview_private.revalidate_for_commit($1,$2,$3)',[frozen.id,correctionPreview.source_fingerprint,correctionPreview.original_invoice_fingerprint]);
  const syntheticGateMs=Date.now()-gateStart;await db.query('rollback');
  await writer.query("insert into attendance_entries(company_id,site_id,worker_id,work_date,work_category,base_man_days) values($1,$2,$3,'2026-10-28','day',1)",[company,site,worker]);
  await assert.rejects(db.query('select invoice_correction_preview_private.revalidate_for_commit($1,$2,$3)',[frozen.id,correctionPreview.source_fingerprint,correctionPreview.original_invoice_fingerprint]),/invoice_revision_stale/);
  await db.query("delete from attendance_entries where company_id=$1 and site_id=$2 and work_date='2026-10-28'",[company,site]);
  await writer.query('begin');await writer.query('update companies set tax_rate=tax_rate where id=$1',[company]);
  await assert.rejects(db.query('select invoice_correction_preview_private.revalidate_for_commit($1,$2,$3)',[frozen.id,correctionPreview.source_fingerprint,correctionPreview.original_invoice_fingerprint]),/lock timeout/);
  await writer.query('rollback');
  assert.deepEqual((await db.query('select * from invoices where id=$1',[frozen.id])).rows[0],frozen);
  console.log(JSON.stringify({synthetic_final_gate_ms:syntheticGateMs,stale_rejected:true,gate_timeout_no_invoice_change:true}));
  // Model a real nonparticipant in authorization: permissions are not among the 28 locks.
  const featureBody=(await db.query("select pg_get_functiondef('private.has_company_feature(uuid,text)'::regprocedure) v")).rows[0].v;
  await db.exec("create table public.synthetic_permission(company_id uuid primary key, allowed boolean not null); create or replace function private.has_company_feature(p_company uuid,p_feature text) returns boolean language sql as $$select coalesce((select allowed from public.synthetic_permission where company_id=p_company),false)$$;");
  await db.query('insert into public.synthetic_permission values($1,true)',[company]);
  const authPreview=(await db.query('select invoice_correction_preview_private.preview($1) v',[frozen.id])).rows[0].v;
  await db.query('begin');
  await db.query('select invoice_correction_preview_private.revalidate_for_commit($1,$2,$3)',[frozen.id,authPreview.source_fingerprint,authPreview.original_invoice_fingerprint]);
  await writer.query('update public.synthetic_permission set allowed=false where company_id=$1',[company]);
  await db.query('commit');
  await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_not_allowed/);
  await db.exec(featureBody);await db.exec('drop table public.synthetic_permission');
  console.log(JSON.stringify({permission_revocation_race_reproduced:true,publication_must_remain_disabled:true}));
  // Experimental global locking does block an unrelated company's insert.
  await db.query('begin');await readLocked();
  await writer.query("set lock_timeout='500ms'");const started=Date.now();
  await assert.rejects(writer.query("insert into companies(id,tax_rate,name) values($1,10,'別の合成会社')",[id(999)]),/lock timeout/);
  const blockedMs=Date.now()-started;assert.ok(blockedMs>=400&&blockedMs<4000);
  await db.query('rollback');await writer.query('reset lock_timeout');
  console.log(JSON.stringify({native_two_session_update_wait:true,native_insert_phantom_wait:true,writer_blocked_until_commit:true,staged_fingerprint_recheck:true,serializable_stage_can_be_stale:true,unrelated_company_blocked_ms:blockedMs}));
 }finally{await writer.query('rollback').catch(()=>{});await writer.end();}
}

await db.query('update site_financial_settings set billing_unit_price_yen=billing_unit_price_yen+1 where company_id=$1 and site_id=$2',[company,site]);
await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_saved_basis_changed/);
await db.query('update site_financial_settings set billing_unit_price_yen=billing_unit_price_yen-1 where company_id=$1 and site_id=$2',[company,site]);
const originalRefresh=(await db.query("select pg_get_functiondef('private.refresh_automatic_invoice(uuid,uuid,date)'::regprocedure) v")).rows[0].v;
const changedRefresh=originalRefresh.replace('declare'+String.fromCharCode(10),'declare'+String.fromCharCode(10)+' -- synthetic calculator drift'+String.fromCharCode(10));assert.notEqual(changedRefresh,originalRefresh);
await db.exec(changedRefresh);await assert.rejects(db.query('select invoice_correction_preview_private.preview($1)',[frozen.id]),/invoice_revision_calculator_changed/);
await db.exec(originalRefresh);

console.log(JSON.stringify({invoice_correction_preview:true,real_refresh_equality:true,original_frozen_unchanged:true,saved_price_drift_rejected:true,route_expense_adjustment_equality:true,unauthorized_denied:true,synthetic_five_to_seven_days:true}));await db.close();process.exit(0);
`;
const generated=resolve(root,'tool/verify_correction_preview.generated.mjs');
try {await writeFile(generated,original.replace(marker,()=>payload+marker).replace('error:error.message,where:error.where','error:error.message,where:error.where,query:error.query?.slice(0,1500)'));const r=spawnSync(process.execPath,[generated,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(generated).catch(()=>{});}
