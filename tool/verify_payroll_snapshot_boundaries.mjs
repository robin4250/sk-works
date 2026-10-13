// Disposable actual-function regression, never a Supabase connection.
// Reuse the existing latest paid-leave harness prerequisites, not copied SQL.
// node tool/verify_payroll_snapshot_boundaries.mjs /path/to/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let source=fs.readFileSync(path.join(root,'tool/verify_paid_leave_wage_sql.mjs'),'utf8');
function replaceOnce(oldText,newText){
 if(source.split(oldText).length!==2) throw new Error(`Upstream harness changed: ${oldText}`);
 source=source.replace(oldText,()=>newText);
}
replaceOnce("const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');",`const root=${JSON.stringify(root)};`);
replaceOnce(" await db.exec(read('supabase/tests/payroll_named_financial_detail_assertions.sql'));",'');
replaceOnce(" await db.exec(read('supabase/tests/paid_leave_wage_assertions.sql'));",'');
const assertions=`do $$declare
 cid uuid:='10000000-0000-0000-0000-000000000001';
 wid uuid:='40000000-0000-0000-0000-000000000001';
 ps public.payroll_statements%rowtype; frozen jsonb; audits integer; state text;
begin
 delete from public.attendance_entries; delete from public.payroll_statements;
 update public.worker_payroll_settings set pay_type='monthly',monthly_salary_yen=300000,
 family_monthly=2000,income_tax_monthly=1000,resident_tax_monthly=2000,social_insurance_monthly=3000,
 custom_earnings='[{"name":"資格","amount_yen":5000}]',custom_deductions='[{"name":"道具","amount_yen":400}]'
 where company_id=cid and worker_id=wid;
 perform private.refresh_automatic_payroll_internal(cid,wid,date '2026-08-01');
 perform private.sync_payroll_attendance_detail(cid,wid,date '2026-08-01');
 select * into strict ps from public.payroll_statements where company_id=cid and worker_id=wid and period_start='2026-08-01';
 if ps.gross_pay<>307000 or ps.deductions<>6400 or ps.net_pay<>300600 then raise exception 'legacy fixed money compatibility'; end if;
 update public.payroll_statements set approved_ids=array['00000000-0000-0000-0000-000000000002'::uuid] where id=ps.id;
 update public.worker_payroll_settings set income_tax_monthly=1500 where company_id=cid and worker_id=wid;
 select * into strict ps from public.payroll_statements where id=ps.id;
 if ps.deductions<>6900 or ps.revision<=1 or cardinality(ps.approved_ids)<>0 then raise exception 'draft change must invalidate approval'; end if;
 foreach state in array array['finalized','manual'] loop
  if state='finalized' then update public.payroll_statements set workflow_state='finalized' where id=ps.id;
  else update public.payroll_statements set workflow_state='draft',automatic_calculation=false where id=ps.id; end if;
  select to_jsonb(p) into frozen from public.payroll_statements p where id=ps.id;
  select count(*) into audits from public.payroll_audit where statement_id=ps.id;
  update public.worker_payroll_settings set family_monthly=family_monthly+777,income_tax_monthly=income_tax_monthly+111 where company_id=cid and worker_id=wid;
  insert into public.attendance_entries(company_id,worker_id,work_date,work_category,base_man_days,overtime_hours,early_hours)
  values(cid,wid,date '2026-08-02','day',1,2,1);
  insert into public.paid_leave_requests(company_id,worker_id,leave_date,status) values(cid,wid,date '2026-08-03','approved');
  perform private.refresh_automatic_payroll_internal(cid,wid,date '2026-08-01');
  perform private.sync_payroll_attendance_detail(cid,wid,date '2026-08-01');
  if (select to_jsonb(p) from public.payroll_statements p where id=ps.id) is distinct from frozen then raise exception '% changed by source refresh',state; end if;
  if (select count(*) from public.payroll_audit where statement_id=ps.id)<>audits then raise exception '% added recalculation audit',state; end if;
 end loop;
end $$;`;
replaceOnce(" console.log('Paid leave wage actual-trigger assertions passed');",` await db.exec(${JSON.stringify(assertions)}); console.log('PASS latest actual calculator: legacy fixed totals, draft revision/approval invalidation, full finalized/manual row and audit preservation after settings/attendance/leave edits');`);
await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
