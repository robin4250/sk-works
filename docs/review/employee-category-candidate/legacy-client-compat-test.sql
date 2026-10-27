-- Synthetic database only. The old backend has no category schema or RPC.
begin;
select set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
do $$ declare wid uuid:='30000000-0000-0000-0000-000000000001'; payload jsonb; result jsonb;
begin
  assert to_regprocedure('public.ensure_employee_categories(uuid)') is null;
  payload:=private.worker_personnel_payload(wid) || jsonb_build_object('department','合成部署');
  assert not payload ? 'employee_category_id';
  result:=public.save_worker_personnel_profile(wid,payload);
  assert result->>'status'='saved';
  assert (select department from public.workers where id=wid)='合成部署';
  payload:=private.worker_personnel_payload(wid) || jsonb_build_object('department','合成部署変更');
  result:=public.save_worker_personnel_profile(wid,payload);
  assert result->>'status'='saved';
  assert (select department from public.workers where id=wid)='合成部署変更';
end $$;
rollback;
