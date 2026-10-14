-- Read existing server-written operations only. No auth configuration or log mutation.
create function private.read_master_self_operation_audit(p_cutoff timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb; cutoff timestamptz;
begin
 cid:=private.security_incident_actor_company();
 cutoff:=date_trunc('milliseconds',coalesce(p_cutoff,clock_timestamp()));
 if not isfinite(cutoff) or cutoff>clock_timestamp() or cutoff<clock_timestamp()-interval '7 days' then raise exception 'audit cutoff unavailable';end if;
 -- Do not return details, identifiers, emails, device names, IPs, or unknown actions.
 select coalesce(jsonb_agg(jsonb_build_object(
  'action',a.action,
  'at',to_char(a.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
 ) order by a.created_at desc,a.id desc),'[]'::jsonb) into result
 from (select id,action,created_at from private.master_admin_audit_log
  where actor_user_id=auth.uid() and target_user_id=auth.uid()
   and created_at<=cutoff
   and action in ('master_device_bootstrap','master_device_lock','master_device_unlock',
    'master_device_revoke','master_recovery_contacts_update',
    'master_recovery_challenge_issued','master_recovery_code_verified',
    'master_recovery_device_registered')
  order by created_at desc,id desc limit 100) a;
 return jsonb_build_object('version',1,'source_provenance','server_master_operation_audit',
  'scope','self_master_account','limit',100,'cutoff',to_char(cutoff at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'events',result);
end $$;
create function public.master_self_operation_audit(p_cutoff timestamptz default null) returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.read_master_self_operation_audit(p_cutoff)
$$;
revoke all on function private.read_master_self_operation_audit(timestamptz),public.master_self_operation_audit(timestamptz) from public,anon,authenticated,service_role;
grant execute on function private.read_master_self_operation_audit(timestamptz),public.master_self_operation_audit(timestamptz) to authenticated;

create function private.read_master_self_auth_audit(p_cutoff timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb; cutoff timestamptz;
begin
 cid:=private.security_incident_actor_company();
 cutoff:=date_trunc('milliseconds',coalesce(p_cutoff,clock_timestamp()));
 if not isfinite(cutoff) or cutoff>clock_timestamp() or cutoff<clock_timestamp()-interval '7 days' then raise exception 'audit cutoff unavailable';end if;
 -- Only the server's actor identity; never infer identity from email or metadata.
 -- Unattributable/failed attempts without this actor are intentionally excluded.
 select coalesce(jsonb_agg(jsonb_build_object(
  'action',a.action,
  'at',to_char(a.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
 ) order by a.created_at desc,a.id desc),'[]'::jsonb) into result
 from (select id,payload->>'action' as action,created_at from auth.audit_log_entries
  where payload->>'actor_id'=auth.uid()::text and created_at<=cutoff
   and payload->>'action' in ('login','logout','user_recovery_requested',
    'user_reauthenticate_requested','user_confirmation_requested',
    'user_updated_password','token_revoked','token_refreshed',
    'factor_in_progress','factor_unenrolled','challenge_created',
    'verification_attempted','factor_deleted','factor_updated',
    'mfa_code_login','identity_unlinked')
  order by created_at desc,id desc limit 100) a;
 return jsonb_build_object('version',1,'source_provenance','supabase_auth_database_audit',
  'scope','self_master_account','limit',100,'cutoff',to_char(cutoff at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'events',result);
end $$;
create function public.master_self_auth_audit(p_cutoff timestamptz default null) returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.read_master_self_auth_audit(p_cutoff)
$$;
revoke all on function private.read_master_self_auth_audit(timestamptz),public.master_self_auth_audit(timestamptz) from public,anon,authenticated,service_role;
grant execute on function private.read_master_self_auth_audit(timestamptz),public.master_self_auth_audit(timestamptz) to authenticated;
