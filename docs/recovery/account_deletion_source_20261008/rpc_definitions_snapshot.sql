-- READ-ONLY CATALOG SNAPSHOT. NOT A MIGRATION. DO NOT EXECUTE.
-- pg_get_functiondef output retained for review only; no account rows were queried.

-- private.confirm_account_deletion_notice(p_id uuid, p_lease uuid, p_receipt text)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION private.confirm_account_deletion_notice(p_id uuid, p_lease uuid, p_receipt text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; n private.account_deletion_notices%rowtype;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps<>array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent','erasePersonalFiles','eraseAuthAccount','verifyErasure']::text[] then raise exception 'erasure_unverified'; end if;
 if p_receipt is null or p_receipt !~ '^[A-Za-z0-9_-]{1,200}$' then raise exception 'invalid_receipt'; end if;
 select * into n from private.account_deletion_notices where job_id=p_id for update;
 if n.state='sent' then return n.provider_receipt=p_receipt; end if;
 if n.state is distinct from 'reserved' then raise exception 'notice_not_reserved'; end if;
 -- Address is no longer needed after the provider confirms acceptance.
 update private.account_deletion_notices set state='sent',sent_at=now(),provider_receipt=p_receipt,recipient=null where job_id=p_id;
 return true;
end $function$


-- private.prepare_account_deletion_notice(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION private.prepare_account_deletion_notice(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; address text;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if exists(select 1 from private.account_deletion_notices where job_id=p_id) then return true; end if;
 if cardinality(j.completed_steps)>1 then raise exception 'notice_preparation_too_late'; end if;
 select email into address from auth.users where id=j.target_user_id and email_confirmed_at is not null;
 if address is null or address !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'verified_contact_required'; end if;
 insert into private.account_deletion_notices(job_id,recipient) values(p_id,address);
 return true;
end $function$


-- private.reserve_account_deletion_notice(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION private.reserve_account_deletion_notice(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; n private.account_deletion_notices%rowtype;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps<>array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent','erasePersonalFiles','eraseAuthAccount','verifyErasure']::text[] then raise exception 'erasure_unverified'; end if;
 select * into n from private.account_deletion_notices where job_id=p_id for update;
 if not found then raise exception 'notice_not_prepared'; end if;
 if n.state='sent' then return jsonb_build_object('state','sent'); end if;
 if n.state='reserved' then raise exception 'delivery_reconciliation_required'; end if;
 update private.account_deletion_notices set state='reserved',reserved_at=now() where job_id=p_id;
 return jsonb_build_object('state','reserved','requestId',p_id,'recipient',n.recipient);
end $function$


-- public.advance_account_deletion_job(p_id uuid, p_lease uuid, p_action text, p_step text)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.advance_account_deletion_job(p_id uuid, p_lease uuid, p_action text, p_step text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; steps text[]:=array[
 'restrictAccess','preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent',
 'erasePersonalFiles','eraseAuthAccount','verifyErasure','notifyCompletion'];
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now() for update;
 if not found then return false; end if;
 if p_action='renew' then
  update private.account_deletion_jobs set lease_until=now()+interval '2 minutes',updated_at=now() where id=p_id;
 elsif p_action='checkpoint' then
  if p_step is null or cardinality(j.completed_steps)>=8 or p_step<>steps[cardinality(j.completed_steps)+1]
   then return false; end if;
  update private.account_deletion_jobs set completed_steps=array_append(completed_steps,p_step),updated_at=now() where id=p_id;
 elsif p_action='complete' then
  if j.completed_steps<>steps then return false; end if;
  update private.account_deletion_jobs set state='completed',lease_until=null,lease_token=null,updated_at=now() where id=p_id;
  update private.account_deletion_requests set status='completed',completed_at=now() where id=p_id;
 elsif p_action='fail' then
  if p_step is null or not (p_step='eligibility' or p_step=any(steps)) then return false; end if;
  update private.account_deletion_jobs set state='failed',failed_step=p_step,lease_until=null,lease_token=null,updated_at=now() where id=p_id;
  update private.account_deletion_requests set status='failed' where id=p_id;
 else return false;
 end if;
 return true;
end $function$


-- public.authorize_account_erasure(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.authorize_account_erasure(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; dependencies jsonb;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>now();
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps<>array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent','erasePersonalFiles']
 then raise exception 'prerequisites_incomplete'; end if;
 if not (public.inspect_account_deletion_handoff(p_id,p_lease)->>'handoff_clear')::boolean
 then return null; end if;
 dependencies:=public.inspect_account_deletion_dependencies(p_id,p_lease);
 if not (dependencies->>'auth_delete_dependencies_clear')::boolean then return null; end if;
 return jsonb_build_object('user_id',j.target_user_id);
end $function$


-- public.check_account_deletion_eligibility(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.check_account_deletion_eligibility(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; plan jsonb; f jsonb; path text;
begin
 select * into j from private.account_deletion_jobs where id=p_id
  and state='processing' and lease_token=p_lease and lease_until>clock_timestamp();
 if not found then raise exception 'invalid_lease'; end if;
 if j.policy_version<>'2026-09-26-company-records-retained-v1' then return false; end if;
 select payload into plan from private.account_deletion_file_plans where job_id=p_id;
 if plan is null or plan->>'userId' is distinct from j.target_user_id::text
  or plan->>'policyVersion' is distinct from j.policy_version
  or encode(extensions.digest(plan::text,'sha256'),'hex')<>j.reviewed_plan_digest
 then return false; end if;
 -- Reject plans that the current eraser cannot finish BEFORE access is suspended.
 -- This is only a preflight: later write barriers and erasure guards remain required.
 if jsonb_typeof(plan->'files') is distinct from 'array' then return false; end if;
 for f in select value from jsonb_array_elements(plan->'files') loop
  if jsonb_typeof(f) is distinct from 'object'
   or f->>'bucket' is null or f->>'bucket' not in (
    'profile-photos','attendance-evidence','chat-attachments',
    'communication-albums','communication-notes')
   or f->>'subjectUserId' is distinct from j.target_user_id::text
   or f->'ownershipVerified' is distinct from 'true'::jsonb
   or f->>'disposition' is distinct from 'erase'
   or jsonb_typeof(f->'path') is distinct from 'string'
  then return false; end if;
  path:=f->>'path';
  if length(path)=0 or length(path)>1024 or left(path,1)='/'
   or strpos(path,chr(92))>0 or path ~ '[[:cntrl:]]'
   or exists(select 1 from unnest(string_to_array(path,'/')) segment
    where segment in ('','.','..'))
  then return false; end if;
 end loop;
 -- Auth removal is blocked by remaining ownership, even outside an approved
 -- plan. Do not modify Storage metadata or assume service-copy transfers it.
 if exists(select 1 from storage.objects o
  where (o.owner=j.target_user_id or o.owner_id=j.target_user_id::text)
   and ((o.owner is not null and o.owner<>j.target_user_id)
    or (o.owner_id is not null and o.owner_id<>j.target_user_id::text)
    or not exists(select 1 from jsonb_array_elements(plan->'files') target
     where target->>'bucket'=o.bucket_id and target->>'path'=o.name)))
 then return false; end if;
 return public.account_deletion_company_history_ready(p_id,p_lease)
  and coalesce((public.inspect_account_deletion_handoff(p_id,p_lease)->>'handoff_clear')::boolean,false);
end $function$


-- public.claim_account_deletion_job(p_id uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.claim_account_deletion_job(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype;
begin
 update private.account_deletion_jobs set state='processing',lease_token=gen_random_uuid(),
 lease_until=now()+interval '2 minutes',updated_at=now(),failed_step=null
 where id=p_id and state<>'completed' and (lease_until is null or lease_until<now()) returning * into j;
 if not found then return null; end if;
 update private.account_deletion_requests set status='processing' where id=p_id;
 return jsonb_build_object('id',j.id,'userId',j.target_user_id,'policyVersion',j.policy_version,
 'reviewedPlanDigest',j.reviewed_plan_digest,'completedSteps',to_jsonb(j.completed_steps),'leaseToken',j.lease_token);
end $function$


-- public.confirm_account_deletion_notice(p_id uuid, p_lease uuid, p_receipt text)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.confirm_account_deletion_notice(p_id uuid, p_lease uuid, p_receipt text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.confirm_account_deletion_notice(p_id,p_lease,p_receipt)
$function$


-- public.erase_account_deletion_personal_content(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.erase_account_deletion_personal_content(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; plan jsonb; current_snapshot jsonb;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps<>array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity']
 then raise exception 'prerequisites_incomplete'; end if;
 select payload into plan from private.account_deletion_file_plans where job_id=p_id;
 if plan is null or plan->>'userId' is distinct from j.target_user_id::text
 or plan->>'policyVersion' is distinct from j.policy_version
 or encode(extensions.digest(plan::text,'sha256'),'hex')<>j.reviewed_plan_digest
 then raise exception 'reviewed_plan_mismatch'; end if;
 current_snapshot:=public.account_deletion_personal_snapshot(j.target_user_id);
 if exists(select 1 from private.account_deletion_content_receipts where job_id=p_id) then
  return public.verify_account_deletion_worker_contacts(p_id,p_lease)
   and public.verify_account_deletion_onboarding(p_id,p_lease)
   and not exists(select 1 from jsonb_each_text(current_snapshot->'counts') where value::bigint<>0);
 end if;
 if plan->'recordDigests' is distinct from current_snapshot->'digests'
 then raise exception 'personal_content_changed'; end if;

 -- Do not cascade-delete someone else's attachment on this user's message.
 if exists(select 1 from public.chat_attachments a join public.chat_messages m on m.id=a.message_id
  where m.sender_user_id=j.target_user_id and a.uploaded_by is distinct from j.target_user_id)
 then raise exception 'shared_attachment_requires_review'; end if;
 -- Notes can be edited by other participants; do not erase their files.
 if exists(select 1 from public.communication_notes n
  cross join lateral jsonb_array_elements(n.attachments) a
  where n.created_by=j.target_user_id and split_part(a->>'path','/',3) is distinct from j.target_user_id::text)
 then raise exception 'shared_attachment_requires_review'; end if;
 -- Before removing file references, ensure every path is already in the fixed
 -- erasure plan. The Storage adapter later removes the actual bytes.
 if exists(select 1 from (
  select 'chat-attachments' as bucket,storage_path as path from public.chat_attachments where uploaded_by=j.target_user_id
  union all select 'profile-photos',avatar_storage_path from public.user_profiles
   where user_id=j.target_user_id and avatar_storage_path is not null
  union all select 'communication-albums',storage_path from public.communication_album_items where uploaded_by=j.target_user_id
  union all select 'communication-notes',a->>'path' from public.communication_notes n
   cross join lateral jsonb_array_elements(n.attachments) a where n.created_by=j.target_user_id
 ) targets where not exists(select 1 from jsonb_array_elements(plan->'files') f
  where f->>'bucket'=targets.bucket and f->>'path'=targets.path
   and f->>'subjectUserId'=j.target_user_id::text and f->>'disposition'='erase'
   and f->'ownershipVerified'='true'::jsonb))
 then raise exception 'file_missing_from_reviewed_plan'; end if;

 if not public.erase_account_deletion_worker_contacts(p_id,p_lease)
 then raise exception 'worker_contact_erasure_unconfirmed'; end if;
 if not public.erase_account_deletion_onboarding(p_id,p_lease)
 then raise exception 'onboarding_erasure_unconfirmed'; end if;
 delete from public.chat_attachments where uploaded_by=j.target_user_id;
 delete from public.communication_album_items where uploaded_by=j.target_user_id;
 -- Keep the other person's moderation report, remove this user's copied post.
 update private.chat_reports set sender_id=null,sender_name=null,body_snapshot='[deleted]'
  where sender_id=j.target_user_id;
 delete from public.chat_messages where sender_user_id=j.target_user_id;
 delete from public.communication_notes where created_by=j.target_user_id;
 delete from public.app_notifications where recipient_user_id=j.target_user_id;
 delete from public.member_language_preferences where user_id=j.target_user_id;
 delete from public.user_profiles where user_id=j.target_user_id;
 insert into private.account_deletion_content_receipts(job_id) values(p_id);
 return not exists(select 1 from jsonb_each_text(public.account_deletion_personal_snapshot(j.target_user_id)->'counts') where value::bigint<>0);
end $function$


-- public.get_account_deletion_status(p_user uuid, p_session uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_account_deletion_status(p_user uuid, p_session uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r private.account_deletion_requests%rowtype;
begin
 if p_user is null or not exists(select 1 from auth.sessions where id=p_session and user_id=p_user
   and (not_after is null or not_after > now())) then raise exception 'invalid_session'; end if;
 select * into r from private.account_deletion_requests where user_id=p_user order by created_at desc limit 1;
 if not found then return null; end if;
 return jsonb_build_object('request_id',r.id,'status',r.status,'created_at',r.created_at,'due_at',r.due_at);
end $function$


-- public.inspect_account_deletion_access_controls()
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.inspect_account_deletion_access_controls()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select jsonb_build_object(
  'data_api_barrier_observed',coalesce(current_setting('sko.account_access_barrier_ran',true),'')='data-api-v1',
  'data_api_hook_observed',coalesce(current_setting('sko.account_access_hook_ran',true),'')='true',
  'rls_guards_installed',not exists(
   select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
   where c.relkind in ('r','p') and (n.nspname='public' or (n.nspname='storage' and c.relname='objects'))
   and (has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')
    or has_any_column_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE'))
   and (not c.relrowsecurity or not exists(
    select 1 from pg_catalog.pg_policy p where p.polrelid=c.oid and p.polname='account_deletion_access_guard'
    and not p.polpermissive and p.polcmd='*'
    and p.polroles=array[(select oid from pg_catalog.pg_roles where rolname='authenticated')]
    and regexp_replace(pg_get_expr(p.polqual,p.polrelid),'\s','','g')='(SELECTprivate.account_access_allowed()ASaccount_access_allowed)'
    and regexp_replace(pg_get_expr(p.polwithcheck,p.polrelid),'\s','','g')='(SELECTprivate.account_access_allowed()ASaccount_access_allowed)'
   ))),
  'scope','data-api-and-rls-only')
$function$


-- public.inspect_account_deletion_execution_readiness()
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.inspect_account_deletion_execution_readiness()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select public.inspect_account_deletion_access_controls()||jsonb_build_object(
  'google_revocation_evidence_ready',
   exists(select 1 from pg_catalog.pg_attribute where attrelid='private.account_deletion_google_credentials'::regclass and attname='revocation_evidence' and not attisdropped)
   and to_regprocedure('public.read_account_deletion_google_revocation_evidence(uuid,uuid,text)') is not null
   and to_regprocedure('public.write_account_deletion_google_revocation_evidence(uuid,uuid,text,text,jsonb)') is not null
   and not has_function_privilege('authenticated','public.read_account_deletion_google_revocation_evidence(uuid,uuid,text)','EXECUTE')
   and not has_function_privilege('anon','public.write_account_deletion_google_revocation_evidence(uuid,uuid,text,text,jsonb)','EXECUTE'),
  'erasure_evidence_ready',
   to_regprocedure('public.read_account_deletion_erasure_evidence(uuid,uuid)') is not null
   and to_regprocedure('public.write_account_deletion_erasure_evidence(uuid,uuid,jsonb)') is not null
   and to_regprocedure('public.inspect_account_deletion_live_guards(uuid,uuid)') is not null
   and exists(select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relname='account_deletion_erasure_evidence' and c.relrowsecurity
     and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')
     and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')))
$function$


-- public.inspect_account_deletion_guard_plan(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.inspect_account_deletion_guard_plan(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; plan jsonb;
begin
 select * into j from private.account_deletion_jobs where id=p_id
  and state='processing' and lease_token=p_lease and lease_until>clock_timestamp();
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps[1] is distinct from 'restrictAccess'
  or not exists(select 1 from private.account_deletion_access_restrictions
   where user_id=j.target_user_id and job_id=j.id)
 then raise exception 'prerequisites_incomplete'; end if;
 select payload into plan from private.account_deletion_file_plans where job_id=p_id;
 if plan is null or plan->>'userId' is distinct from j.target_user_id::text
  or plan->>'policyVersion' is distinct from j.policy_version
  or encode(extensions.digest(plan::text,'sha256'),'hex')<>j.reviewed_plan_digest
 then raise exception 'reviewed_plan_mismatch'; end if;
 return plan||jsonb_build_object('digest',j.reviewed_plan_digest,'writesRestricted',true);
end $function$


-- public.inspect_account_deletion_live_guards(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.inspect_account_deletion_live_guards(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; base jsonb; old_claims text; old_sub text; allowed boolean;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp() for share;
 if not found then raise exception 'invalid_lease'; end if;
 base:=public.inspect_account_deletion_subject_access(p_id,p_lease);
 old_claims:=current_setting('request.jwt.claims',true);
 old_sub:=current_setting('request.jwt.claim.sub',true);
 -- Evaluate the SAME function used by restrictive Storage/public policies.
 -- This does not issue a JWT or change a role; both settings are transaction local.
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',j.target_user_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',j.target_user_id::text,true);
  allowed:=private.account_access_allowed();
  perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
  perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
 exception when others then
  perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
  perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
  raise;
 end;
 return base||jsonb_build_object('job_id',j.id,
  'storage_guard_denies_subject',allowed is false,
  'storage_buckets_private',not exists(select 1 from storage.buckets where public),
  'server_guard_denies_subject',public.account_server_access_allowed(j.target_user_id) is false);
end $function$


-- public.inspect_account_deletion_subject_access(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.inspect_account_deletion_subject_access(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; restricted_at timestamptz; banned boolean;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>now();
 if not found then raise exception 'invalid_lease'; end if;
 select r.restricted_at into restricted_at from private.account_deletion_access_restrictions r
  where r.user_id=j.target_user_id and r.job_id=p_id;
 select exists(select 1 from auth.users where id=j.target_user_id and banned_until>now()+interval '31 days') into banned;
 return public.inspect_account_deletion_access_controls()||jsonb_build_object(
  'user_id',j.target_user_id,'restriction_present',restricted_at is not null,
  'restricted_at',restricted_at,'auth_ban_confirmed',banned,
  'server_activities_clear',not exists(select 1 from private.account_server_activities where user_id=j.target_user_id));
end $function$


-- public.prepare_account_deletion_notice(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.prepare_account_deletion_notice(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.prepare_account_deletion_notice(p_id,p_lease)
$function$


-- public.preserve_account_deletion_company_records(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.preserve_account_deletion_company_records(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype;
begin
 select * into j from private.account_deletion_jobs where id=p_id
  and state='processing' and lease_token=p_lease and lease_until>now() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if j.policy_version<>'2026-09-26-company-records-retained-v1'
  or j.completed_steps<>array['restrictAccess']
 then raise exception 'retention_prerequisites_incomplete'; end if;

 -- An unexpected pre-existing attribution must never be overwritten.
 if exists(select 1 from public.payroll_audit where actor_id=j.target_user_id
    and retained_actor_id is not null and retained_actor_id<>j.target_user_id)
 or exists(select 1 from public.payroll_statements where finalized_by=j.target_user_id
    and retained_finalized_by is not null and retained_finalized_by<>j.target_user_id)
 or exists(select 1 from private.daily_report_cancellations where actor_id=j.target_user_id
    and retained_actor_id is not null and retained_actor_id<>j.target_user_id)
 then raise exception 'retained_actor_conflict'; end if;

 insert into private.account_deletion_retention_receipts(job_id,fingerprint)
 values(p_id,public.account_deletion_retention_fingerprint(p_id,p_lease))
 on conflict(job_id) do nothing;
 if (select fingerprint from private.account_deletion_retention_receipts where job_id=p_id)
  is distinct from public.account_deletion_retention_fingerprint(p_id,p_lease)
 then raise exception 'retained_record_changed'; end if;

 if not public.preserve_account_deletion_extended_history(p_id,p_lease)
 then raise exception 'extended_history_unconfirmed'; end if;

 update public.payroll_audit set retained_actor_id=actor_id,actor_id=null
  where actor_id=j.target_user_id;
 update public.payroll_statements set retained_finalized_by=finalized_by,finalized_by=null
  where finalized_by=j.target_user_id;
 update private.daily_report_cancellations set retained_actor_id=actor_id,actor_id=null
  where actor_id=j.target_user_id;
 -- Signed reports and invoices have no blocking actor FK requiring changes.
 -- Their contents, amounts, worker identity and signatures remain in place.
 return not exists(select 1 from public.payroll_audit where actor_id=j.target_user_id)
  and not exists(select 1 from public.payroll_statements where finalized_by=j.target_user_id)
  and not exists(select 1 from private.daily_report_cancellations where actor_id=j.target_user_id);
end $function$


-- public.read_account_deletion_erasure_evidence(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.read_account_deletion_erasure_evidence(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform 1 from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp() for share;
 if not found then raise exception 'invalid_lease'; end if;
 perform public.read_account_deletion_file_plan(p_id,p_lease);
 select envelope into result from private.account_deletion_erasure_evidence where job_id=p_id;
 return result;
end $function$


-- public.read_account_deletion_file_plan(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.read_account_deletion_file_plan(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; plan jsonb;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now();
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps[1:4] is distinct from array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity','erasePersonalContent']
 then raise exception 'prerequisites_incomplete'; end if;
 select payload into plan from private.account_deletion_file_plans where job_id=p_id;
 if plan is null or plan->>'userId' is distinct from j.target_user_id::text
 or plan->>'policyVersion' is distinct from j.policy_version
 or encode(extensions.digest(plan::text,'sha256'),'hex')<>j.reviewed_plan_digest
 then raise exception 'reviewed_plan_mismatch'; end if;
 return plan||jsonb_build_object('digest',j.reviewed_plan_digest,'writesRestricted',true);
end $function$


-- public.read_account_deletion_google_credential(p_id uuid, p_lease uuid, p_identity text)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.read_account_deletion_google_credential(p_id uuid, p_lease uuid, p_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; result jsonb;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>now();
 if not found or 'revokeExternalIdentity'=any(j.completed_steps) then raise exception 'invalid_lease_or_step'; end if;
 select jsonb_build_object('jobId',c.request_id,'userId',c.user_id,'identityId',c.identity_id,
  'clientId',c.client_id,'envelope',c.envelope) into result
 from private.account_deletion_google_credentials c where c.request_id=p_id
  and c.user_id=j.target_user_id and c.identity_id::text=p_identity;
 if result is null then raise exception 'google_credential_unavailable'; end if;
 return result;
end $function$


-- public.read_account_deletion_google_revocation_evidence(p_id uuid, p_lease uuid, p_identity text)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.read_account_deletion_google_revocation_evidence(p_id uuid, p_lease uuid, p_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; c private.account_deletion_google_credentials%rowtype;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp();
 if not found or j.completed_steps is distinct from array['restrictAccess','preserveRequiredRecords']::text[]
 then raise exception 'invalid_lease_or_step'; end if;
 select * into c from private.account_deletion_google_credentials
 where request_id=p_id and user_id=j.target_user_id and identity_id::text=p_identity;
 if not found then raise exception 'google_credential_unavailable'; end if;
 if c.revocation_evidence is null then return null; end if;
 return jsonb_build_object('jobId',p_id,'userId',j.target_user_id,'identityId',c.identity_id,
  'clientId',c.client_id,'planDigest',j.reviewed_plan_digest,'envelope',c.revocation_evidence);
end $function$


-- public.request_account_deletion(p_user uuid, p_session uuid, p_policy text, p_days integer)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.request_account_deletion(p_user uuid, p_session uuid, p_policy text, p_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r private.account_deletion_requests%rowtype;
begin
 if p_user is null or not exists(select 1 from auth.sessions where id=p_session and user_id=p_user
  and (not_after is null or not_after > now()))
 then raise exception 'invalid_session'; end if;
 if p_policy is null or length(p_policy) not between 1 and 100 or p_days is null or p_days not between 1 and 90
 then raise exception 'invalid_policy'; end if;
 perform pg_advisory_xact_lock(hashtextextended('account-deletion:'||p_user::text,0));
 select * into r from private.account_deletion_requests where user_id=p_user
  and status in ('requested','processing','failed');
 if not found then
  insert into private.account_deletion_requests(user_id,policy_version,due_at)
  values(p_user,p_policy,now()+make_interval(days=>p_days)) returning * into r;
 end if;
 return jsonb_build_object('request_id',r.id,'status',r.status,'created_at',r.created_at,'due_at',r.due_at);
end $function$


-- public.request_account_deletion_with_google(p_user uuid, p_session uuid, p_policy text, p_days integer, p_credential jsonb)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.request_account_deletion_with_google(p_user uuid, p_session uuid, p_policy text, p_days integer, p_credential jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare receipt jsonb; request_id uuid;
begin
 if p_credential->>'userId' is distinct from p_user::text
  or not exists(select 1 from auth.identities where user_id=p_user and provider='google'
   and id::text=p_credential->>'identityId')
  or jsonb_typeof(p_credential->'envelope') is distinct from 'object'
  or p_credential->'envelope'->>'version' is distinct from '1'
  or coalesce(p_credential->'envelope'->>'iv','') !~ '^[A-Za-z0-9+/]{16}$'
  or coalesce(p_credential->'envelope'->>'ciphertext','') !~ '^[A-Za-z0-9+/]+={0,2}$'
  or length(coalesce(p_credential->'envelope'->>'ciphertext','')) not between 24 and 12000
  or length(coalesce(p_credential->>'clientId','')) not between 1 and 256
 then raise exception 'invalid_google_credential'; end if;
 receipt:=public.request_account_deletion(p_user,p_session,p_policy,p_days);
 request_id:=(receipt->>'request_id')::uuid;
 if receipt->>'status'<>'requested' or exists(select 1 from private.account_deletion_jobs where id=request_id)
 then raise exception 'deletion_already_processing'; end if;
 insert into private.account_deletion_google_credentials(request_id,user_id,identity_id,client_id,envelope)
 values(request_id,p_user,(p_credential->>'identityId')::uuid,p_credential->>'clientId',p_credential->'envelope')
 on conflict on constraint account_deletion_google_credentials_pkey do update
 set identity_id=excluded.identity_id,client_id=excluded.client_id,envelope=excluded.envelope,created_at=now();
 return receipt;
end $function$


-- public.reserve_account_deletion_notice(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.reserve_account_deletion_notice(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.reserve_account_deletion_notice(p_id,p_lease)
$function$


-- public.restrict_account_deletion_data_access(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.restrict_account_deletion_data_access(p_id uuid, p_lease uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; plan jsonb;
begin
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
  raise exception 'account_access_isolation_unsupported';
 end if;
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp() for update;
 if not found then raise exception 'invalid_lease'; end if;
 if cardinality(j.completed_steps)<>0 then raise exception 'prerequisites_incomplete'; end if;
 -- Never wait while holding a job row lock, or continue past an active request.
 -- A busy subject produces a retryable failure, not a successful restriction.
 if not pg_catalog.pg_try_advisory_xact_lock(private.account_deletion_barrier_key(j.target_user_id)) then
  raise exception 'account_requests_in_flight';
 end if;
 if exists(select 1 from private.account_server_activities where user_id=j.target_user_id) then
  raise exception 'account_server_activity_pending';
 end if;
 select payload into plan from private.account_deletion_file_plans where job_id=p_id;
 if plan is null or plan->>'userId' is distinct from j.target_user_id::text
  or encode(extensions.digest(plan::text,'sha256'),'hex')<>j.reviewed_plan_digest
 then raise exception 'reviewed_plan_mismatch'; end if;
 if j.lease_until<=clock_timestamp() then raise exception 'invalid_lease'; end if;
 insert into private.account_deletion_access_restrictions(user_id,job_id)
 values(j.target_user_id,j.id) on conflict(user_id) do nothing;
 return exists(select 1 from private.account_deletion_access_restrictions
  where user_id=j.target_user_id and job_id=j.id);
end $function$


-- public.verify_account_deletion_records(p_id uuid, p_lease uuid)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.verify_account_deletion_records(p_id uuid, p_lease uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype; original jsonb; dep record;
 amount bigint; remaining bigint:=0;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
 and lease_token=p_lease and lease_until>now();
 if not found then raise exception 'invalid_lease'; end if;
 if j.completed_steps<>array['restrictAccess','preserveRequiredRecords','revokeExternalIdentity',
 'erasePersonalContent','erasePersonalFiles','eraseAuthAccount'] then raise exception 'prerequisites_incomplete'; end if;
 select fingerprint into original from private.account_deletion_retention_receipts where job_id=p_id;
 if original is null then raise exception 'retention_receipt_missing'; end if;
 -- Inspect all actual Auth foreign keys, plus explicit non-FK personal links.
 -- Query errors/permission failures abort rather than claiming an empty result.
 for dep in
  select distinct n.nspname as schema_name,r.relname as table_name,a.attname as column_name
   from pg_catalog.pg_constraint c join pg_catalog.pg_class r on r.oid=c.conrelid
   join pg_catalog.pg_namespace n on n.oid=r.relnamespace
   join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
   where c.contype='f' and c.confrelid='auth.users'::regclass and cardinality(c.conkey)=1
    and n.nspname in ('public','private')
  union select * from (values ('public','chat_messages','sender_user_id'),
   ('public','member_language_preferences','user_id'),('private','chat_reports','sender_id'),
   ('private','professional_access_audit','actor_id')) as extra(schema_name,table_name,column_name)
 loop
  execute format('select count(*) from %I.%I where %I=$1',dep.schema_name,dep.table_name,dep.column_name)
   into amount using j.target_user_id;
  remaining:=remaining+amount;
 end loop;
 return jsonb_build_object('user_id',j.target_user_id,'inspection_complete',
 public.verify_account_deletion_worker_contacts(p_id,p_lease)
 and public.verify_account_deletion_onboarding(p_id,p_lease),
 'personal_rows_remaining',remaining,'retained_records_verified',
 original=public.account_deletion_retention_fingerprint(p_id,p_lease)
 and not exists(select 1 from private.professional_invites
  where retained_claimed_by=j.target_user_id and
   (status<>'revoked' or name<>'[deleted]' or phone<>'[deleted]' or profession<>'' or expires_at>now())));
end $function$


-- public.write_account_deletion_erasure_evidence(p_id uuid, p_lease uuid, p_envelope jsonb)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.write_account_deletion_erasure_evidence(p_id uuid, p_lease uuid, p_envelope jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 perform 1 from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp()
  and not ('erasePersonalFiles'=any(completed_steps)) for update;
 if not found then raise exception 'invalid_lease_or_step'; end if;
 perform public.read_account_deletion_file_plan(p_id,p_lease);
 if p_envelope->>'version' is distinct from '1'
  or coalesce(p_envelope->>'iv','') !~ '^[A-Za-z0-9+/]{16}$'
  or coalesce(p_envelope->>'ciphertext','') !~ '^[A-Za-z0-9+/]+={0,2}$'
  or length(coalesce(p_envelope->>'ciphertext','')) not between 24 and 2000000
 then raise exception 'invalid_envelope'; end if;
 insert into private.account_deletion_erasure_evidence(job_id,envelope) values(p_id,p_envelope)
 on conflict(job_id) do update set envelope=excluded.envelope,updated_at=now();
 return true;
end $function$


-- public.write_account_deletion_google_revocation_evidence(p_id uuid, p_lease uuid, p_identity text, p_client text, p_envelope jsonb)
-- Captured ACL: {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.write_account_deletion_google_revocation_evidence(p_id uuid, p_lease uuid, p_identity text, p_client text, p_envelope jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j private.account_deletion_jobs%rowtype;
begin
 select * into j from private.account_deletion_jobs where id=p_id and state='processing'
  and lease_token=p_lease and lease_until>clock_timestamp() for update;
 if not found or j.completed_steps is distinct from array['restrictAccess','preserveRequiredRecords']::text[]
 then raise exception 'invalid_lease_or_step'; end if;
 if jsonb_typeof(p_envelope) is distinct from 'object'
  or p_envelope->>'version' is distinct from '1'
  or coalesce(p_envelope->>'iv','') !~ '^[A-Za-z0-9+/]{16}$'
  or coalesce(p_envelope->>'ciphertext','') !~ '^[A-Za-z0-9+/]+={0,2}$'
  or length(coalesce(p_envelope->>'ciphertext','')) not between 24 and 24000
 then raise exception 'invalid_envelope'; end if;
 update private.account_deletion_google_credentials set revocation_evidence=p_envelope
 where request_id=p_id and user_id=j.target_user_id and identity_id::text=p_identity and client_id=p_client;
 if not found then raise exception 'google_credential_unavailable'; end if;
 return true;
end $function$


