-- Exact C head bbe04e helper body; surrounding sessions remain the existing synthetic fixture.
create function private.require_standalone_trade_document_access() returns jsonb
language plpgsql security definer set search_path='' as $body$
declare sid uuid; companies uuid[];roles text[];
begin
 sid:=private.require_reauthentication_session();
 select array_agg(m.company_id),array_agg(m.role::text) into companies,roles
 from (select company_id,role from public.company_members where user_id=auth.uid() for share) m;
 if coalesce(cardinality(companies),0)<>1 or companies[1] is null or roles[1] is null or roles[1] not in ('owner','admin','manager') then
  raise sqlstate '42501' using message='standalone_company_management_required';
 end if;
 perform private.require_trade_documents_master_feature();
 return jsonb_build_object('contract_version',1,'actor_id',auth.uid(),'session_id',sid,
  'company_id',companies[1],'role',roles[1],'master_enabled',true,'can_generate',true,'context_contract_version',1);
end $body$;
revoke all on function private.require_standalone_trade_document_access() from public,anon,authenticated,service_role;
