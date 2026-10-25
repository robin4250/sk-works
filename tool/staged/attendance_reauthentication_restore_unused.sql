-- REVIEW ONLY: exact unused-module restoration, not an activated rollout rollback.
begin;
do $$begin
 if not exists(select 1 from private.reauthentication_rollout where scope='attendance_management' and not enabled)
  or exists(select 1 from private.reauthentication_proofs where operation='attendance.manage') then
  raise exception 'attendance_reauthentication_unused_restore_only';end if;
end $$;
drop function public.force_manage_attendance_with_proof(text,jsonb,text),
 public.attendance_management_reauthentication_target(text,jsonb),attendance_stepup_private.target(text,jsonb);
do $$declare original record;begin
 for original in select * from attendance_stepup_private.originals loop execute original.definition;end loop;
end $$;
drop function attendance_stepup_private.force_manage_attendance_unproven(text,jsonb);
delete from private.reauthentication_rollout where scope='attendance_management';
alter table private.reauthentication_rollout drop constraint reauthentication_rollout_scope_check;
alter table private.reauthentication_rollout add constraint reauthentication_rollout_scope_check
 check(scope in('secondary_password','master_feature','master_security'));
drop table attendance_stepup_private.originals;
drop schema attendance_stepup_private;
commit;
