-- Synthetic isolated assertions: NEVER execute this file in production.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_config('test.account_access_denied','',false);
update companies set company_seal_style='aoyagi_reisho',name='株式会社テスト建設';
create temp table protected_money as select to_jsonb(p) row from payroll_statements p
 where worker_id<>'40000000-0000-0000-0000-000000000001' or period_end<date_trunc('month',now() at time zone 'Asia/Tokyo')::date;
-- Real manager RPC switches leave -> work -> leave; payroll refresh is invoked only
-- by the existing attendance/leave triggers, never a direct calculator call here.
set role authenticated;
select public.force_manage_attendance('upsert',jsonb_build_array(jsonb_build_object(
 'worker_id','40000000-0000-0000-0000-000000000001','date',(now() at time zone 'Asia/Tokyo')::date,'mode','paid_leave')));
reset role;
do $$declare v_statement public.payroll_statements;begin
 select * into v_statement from payroll_statements where worker_id='40000000-0000-0000-0000-000000000001'
 and period_start=date_trunc('month',now() at time zone 'Asia/Tokyo')::date;
 if v_statement.gross_pay is distinct from 12000 or v_statement.detail->>'有給支給額' is distinct from '12000' then raise exception 'Managed leave did not synchronize actual paid leave money: %',v_statement.detail;end if;
 if v_statement.detail->'company_seal_snapshot'->>'style' is distinct from 'aoyagi_reisho' then raise exception 'New managed leave statement did not snapshot seal';end if;
 if exists(select 1 from attendance_entries where worker_id=v_statement.worker_id and work_date=(now() at time zone 'Asia/Tokyo')::date) then raise exception 'Paid leave overlaps work';end if;
end $$;
set role authenticated;
select public.force_manage_attendance('upsert',jsonb_build_array(jsonb_build_object(
 'worker_id','40000000-0000-0000-0000-000000000001','date',(now() at time zone 'Asia/Tokyo')::date,'mode','work',
 'site_id','70000000-0000-0000-0000-000000000001','clock_in','08:00','clock_out','17:00','overtime_hours',2)));
reset role;
do $$declare v_statement public.payroll_statements;begin
 select * into v_statement from payroll_statements where worker_id='40000000-0000-0000-0000-000000000001'
 and period_start=date_trunc('month',now() at time zone 'Asia/Tokyo')::date;
 if v_statement.gross_pay is distinct from 15126 or coalesce((v_statement.detail->>'有給支給額')::numeric,0)<>0 then raise exception 'Managed work retained leave or wrong work money: %',to_jsonb(v_statement);end if;
 if (select count(*) from attendance_verifications where worker_id=v_statement.worker_id and work_date=(now() at time zone 'Asia/Tokyo')::date)<>2 then raise exception 'Managed work lacks actual paired evidence';end if;
 if exists(select 1 from paid_leave_requests where worker_id=v_statement.worker_id and leave_date=(now() at time zone 'Asia/Tokyo')::date and status='approved') then raise exception 'Work retained approved leave';end if;
end $$;
create temp table work_statement as select id,detail->'company_seal_snapshot' seal from payroll_statements
 where worker_id='40000000-0000-0000-0000-000000000001' and period_start=date_trunc('month',now() at time zone 'Asia/Tokyo')::date;
update companies set name='株式会社改名',company_seal_style='legacy';
-- Updating an existing attendance row (same saved statement) preserves its seal.
update attendance_entries set overtime_hours=3 where worker_id='40000000-0000-0000-0000-000000000001'
 and work_date=(now() at time zone 'Asia/Tokyo')::date;
do $$begin
 if not exists(select 1 from payroll_statements p join work_statement w on p.id=w.id
 where p.gross_pay=16689 and p.detail->'company_seal_snapshot'=w.seal) then raise exception 'Attendance trigger refresh changed stored seal or wrong overtime';end if;
end $$;
set role authenticated;
select public.force_manage_attendance('upsert',jsonb_build_array(jsonb_build_object(
 'worker_id','40000000-0000-0000-0000-000000000001','date',(now() at time zone 'Asia/Tokyo')::date,'mode','paid_leave')));
reset role;
do $$declare v_statement public.payroll_statements;begin
 select * into v_statement from payroll_statements where worker_id='40000000-0000-0000-0000-000000000001'
 and period_start=date_trunc('month',now() at time zone 'Asia/Tokyo')::date;
 if v_statement.gross_pay is distinct from 12000 or v_statement.detail->>'有給支給額' is distinct from '12000' then raise exception 'Work -> leave money not synchronized';end if;
 if v_statement.detail->'company_seal_snapshot'->>'name' is distinct from '株式会社改名' then raise exception 'Newly recreated statement lacks current company snapshot';end if;
 if exists(select 1 from attendance_entries where worker_id=v_statement.worker_id and work_date=(now() at time zone 'Asia/Tokyo')::date)
 or exists(select 1 from attendance_verifications where worker_id=v_statement.worker_id and work_date=(now() at time zone 'Asia/Tokyo')::date)
 then raise exception 'Leave retained work evidence';end if;
 if exists(select 1 from protected_money old where not exists(select 1 from payroll_statements q where to_jsonb(q)=old.row)) then raise exception 'Protected past/manual/finalized payroll full row changed';end if;
 if exists(select 1 from private.vehicle_usage_rollout) or exists(select 1 from private.group_checkout_rollout)
 or exists(select 1 from private.source_notification_rollouts) or exists(select 1 from public.vehicle_usage_claims)
 or exists(select 1 from public.app_notifications) or exists(select 1 from private.source_notification_receipts)
 then raise exception 'OFF integration activated gate, claimed vehicle, or emitted notifications';end if;
end $$;
