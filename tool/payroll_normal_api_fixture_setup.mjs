import fs from 'node:fs';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';
const read=p=>fs.readFileSync(p,'utf8');
export async function setupNormalPayrollFixture(db){
 await setupPayrollScopeFixture(db);
 await db.exec(read('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql'));
 await db.exec(read('supabase/tests/payroll_normal_api_access_fixture.sql'));
 await db.exec(read('supabase/tests/payroll_normal_api_live_source_fixture.sql'));
 // Fixture ACL mirrors client-callable functions; internal capture/lock helpers are never client callable.
 await db.exec(`revoke all on function public.force_manage_attendance(text,jsonb),public.decide_attendance_correction_request(uuid,text,text),public.decide_paid_leave_request(uuid,text,text),public.submit_paid_leave_request(date[],text),public.submit_retrospective_paid_leave_request(date[],text),public.cancel_daily_report(jsonb),public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) from public,anon;grant execute on function public.force_manage_attendance(text,jsonb),public.decide_attendance_correction_request(uuid,text,text),public.decide_paid_leave_request(uuid,text,text),public.submit_paid_leave_request(date[],text),public.submit_retrospective_paid_leave_request(date[],text),public.cancel_daily_report(jsonb),public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) to authenticated;grant execute on function private.cancel_daily_report(jsonb) to authenticated;`);
}
