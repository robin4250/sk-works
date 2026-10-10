-- Opt-in contract. No legacy backfill, no rollout enabled by this migration.
alter table public.attendance_verifications
 add column capture_contract_version smallint,
 add column gps_capture_status text,
 add column photo_capture_status text,
 add column gps_captured_at timestamptz,
 add column photo_captured_at timestamptz,
 add column photo_observed_at timestamptz,
 add column captured_address text;
create table private.attendance_capture_rollouts (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
alter table private.attendance_capture_rollouts enable row level security;
revoke all on private.attendance_capture_rollouts from public, anon, authenticated;
-- Names come from the original two unnamed CHECKs. Fail rather than silently
-- dropping a different constraint when the deployed schema is unexpected.
do $$ declare gps_definition text; photo_definition text; begin
 select regexp_replace(lower(pg_get_expr(conbin,conrelid)), '\s+', '', 'g') into gps_definition
 from pg_constraint where conrelid='public.attendance_verifications'::regclass
 and contype='c' and conname='attendance_verifications_check';
 select regexp_replace(lower(pg_get_expr(conbin,conrelid)), '\s+', '', 'g') into photo_definition
 from pg_constraint where conrelid='public.attendance_verifications'::regclass
 and contype='c' and conname='attendance_verifications_check1';
 if gps_definition is distinct from '((verification_mode=''manual''::text)or((latitudeisnotnull)and(longitudeisnotnull)))'
 or photo_definition is distinct from '((verification_mode<>''location_photo''::text)or(photo_storage_pathisnotnull))' then
  raise exception 'original attendance capture constraints are missing or changed';
 end if;
end $$;
alter table public.attendance_verifications drop constraint attendance_verifications_check;
alter table public.attendance_verifications drop constraint attendance_verifications_check1;
alter table public.attendance_verifications add constraint attendance_capture_contract_check check ((
 (capture_contract_version is null and gps_capture_status is null and photo_capture_status is null
  and gps_captured_at is null and photo_captured_at is null and photo_observed_at is null and captured_address is null
  and (verification_mode='manual' or (latitude is not null and longitude is not null))
  and (verification_mode<>'location_photo' or photo_storage_path is not null))
 or
 (capture_contract_version=1 and verification_mode='location_photo'
  and gps_capture_status is not null and photo_capture_status is not null
  and (
   (gps_capture_status='acquired' and latitude between -90 and 90 and longitude between -180 and 180
    and latitude is not null and longitude is not null and gps_captured_at is not null
    and (accuracy_m is null or accuracy_m>=0))
   or (gps_capture_status in ('failed','missing') and latitude is null and longitude is null
    and accuracy_m is null and distance_to_site_m is null and gps_captured_at is null
    and captured_address is null and proximity_status='not_checked')
  )
  and (
   (photo_capture_status='uploaded' and nullif(btrim(photo_storage_path),'') is not null and photo_observed_at is not null)
   or (photo_capture_status='upload_failed' and photo_storage_path is null and photo_observed_at is not null)
   or (photo_capture_status in ('failed','missing') and photo_storage_path is null and photo_captured_at is null and photo_observed_at is null)
  )
 )
) is true);
create function private.guard_attendance_capture_contract() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' then
  if (OLD.capture_contract_version is not null or NEW.capture_contract_version is not null)
   and row(NEW.capture_contract_version,NEW.gps_capture_status,NEW.photo_capture_status,NEW.gps_captured_at,
    NEW.photo_captured_at,NEW.photo_observed_at,NEW.captured_address,NEW.latitude,NEW.longitude,NEW.accuracy_m,
    NEW.distance_to_site_m,NEW.proximity_status,NEW.photo_storage_path,NEW.verification_mode)
    is distinct from row(OLD.capture_contract_version,OLD.gps_capture_status,OLD.photo_capture_status,OLD.gps_captured_at,
    OLD.photo_captured_at,OLD.photo_observed_at,OLD.captured_address,OLD.latitude,OLD.longitude,OLD.accuracy_m,
    OLD.distance_to_site_m,OLD.proximity_status,OLD.photo_storage_path,OLD.verification_mode) then
   raise exception 'captured attendance evidence is immutable';
  end if;
 elsif NEW.capture_contract_version is not null and not exists (
  select 1 from private.attendance_capture_rollouts r where r.company_id=NEW.company_id and r.enabled
 ) then raise exception 'attendance capture contract is not enabled';
 end if;
 return NEW;
end $$;
revoke all on function private.guard_attendance_capture_contract() from public,anon,authenticated;
create trigger attendance_capture_contract_guard before insert or update on public.attendance_verifications
 for each row execute function private.guard_attendance_capture_contract();

-- Readiness is scoped to existing company membership and account access.
-- No endpoint can enable the rollout or read another company's configuration.
create function private.get_attendance_capture_capability(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.account_access_allowed() or not exists (
  select 1 from public.company_members cm where cm.company_id=p_company_id and cm.user_id=auth.uid()
 ) then raise exception 'attendance capture capability is unavailable' using errcode='42501'; end if;
 return jsonb_build_object('version',1,'company_id',p_company_id,'capture_enabled',
  exists(select 1 from private.attendance_capture_rollouts r where r.company_id=p_company_id and r.enabled));
end $$;
revoke all on function private.get_attendance_capture_capability(uuid) from public,anon;
grant execute on function private.get_attendance_capture_capability(uuid) to authenticated;
create function public.get_attendance_capture_capability(p_company_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select private.get_attendance_capture_capability(p_company_id)
$$;
revoke all on function public.get_attendance_capture_capability(uuid) from public,anon;
grant execute on function public.get_attendance_capture_capability(uuid) to authenticated;
