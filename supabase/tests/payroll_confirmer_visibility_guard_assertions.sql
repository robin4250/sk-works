-- Run after payroll_assigned_confirmation_assertions in the disposable fixture.
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.set_payroll_confirmers(array['00000000-0000-0000-0000-000000000001'::uuid]);
do $$begin
 if exists(select 1 from public.payroll_confirmation_candidates() where user_id='00000000-0000-0000-0000-000000000003') then raise exception 'invisible manager offered'; end if;
 begin
 perform public.set_payroll_confirmers(array['00000000-0000-0000-0000-000000000003'::uuid]);
 raise exception 'invisible manager accepted';
 exception when others then if sqlerrm<>'サブ管理者を確認者にするには、全社員の給与閲覧権限が必要です。' then raise; end if; end;
 if (select count(*) from public.payroll_confirmers where user_id='00000000-0000-0000-0000-000000000001')<>1 then raise exception 'invalid save destroyed assignment'; end if;
 begin perform public.set_payroll_confirmers(array['00000000-0000-0000-0000-000000000004'::uuid]); raise exception 'foreign member accepted'; exception when others then if sqlerrm<>'invalid company confirmer' then raise; end if; end;
end $$;
insert into public.payroll_manager_worker_visibility(company_id,worker_id,visible_to_manager)
select company_id,id,true from public.workers where company_id='10000000-0000-0000-0000-000000000001' and affiliation::text='employee'
on conflict(company_id,worker_id) do update set visible_to_manager=true;
do $$begin
 if not exists(select 1 from public.payroll_confirmation_candidates() where user_id='00000000-0000-0000-0000-000000000003') then raise exception 'fully visible manager missing'; end if;
 perform public.set_payroll_confirmers(array['00000000-0000-0000-0000-000000000003'::uuid]);
end $$;
update public.payroll_manager_worker_visibility set visible_to_manager=false where worker_id='40000000-0000-0000-0000-000000000001';
do $$begin
 if not exists(select 1 from public.payroll_confirmation_candidates() where user_id='00000000-0000-0000-0000-000000000003' and selected_position=1) then raise exception 'existing invalid selection hidden'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$begin
 if (public.payroll_confirmation_status('2026-08-01')->>'can_confirm')::boolean then raise exception 'status allows revoked visibility'; end if;
 if (public.payroll_review_workspace('2026-08-01')->>'can_confirm')::boolean then raise exception 'workspace allows revoked visibility'; end if;
 begin perform public.confirm_payroll_review_month('2026-08-01'); raise exception 'direct confirmation bypassed visibility'; exception when others then if sqlerrm<>'payroll visibility required' then raise; end if; end;
 if has_function_privilege('anon','public.set_payroll_confirmers(uuid[])','EXECUTE') or has_function_privilege('authenticated','private.payroll_confirmer_eligible(uuid,uuid,date)','EXECUTE') then raise exception 'function ACL exposed'; end if;
end $$;
rollback;
