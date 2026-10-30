-- Verbatim shared gate from the C review candidate; its prosrc MD5 is guarded
-- by the registration prototype. The surrounding auth implementation is a
-- declared fixture, not a substitute for the production helper or real JWTs.
create function private.require_trade_documents_master_feature() returns void
language plpgsql security definer set search_path='' as $body$
declare flag boolean;
begin
 perform private.require_reauthentication_session();
 select enabled into flag from private.master_feature_settings where feature_key='site_order_documents' for share;
 if not found then
  lock table private.master_feature_settings in share mode;
  select enabled into flag from private.master_feature_settings where feature_key='site_order_documents' for share;
 end if;
 if flag is distinct from true then raise sqlstate '42501' using message='standalone_master_feature_disabled'; end if;
end $body$;
revoke all on function private.require_trade_documents_master_feature() from public,anon,authenticated;
