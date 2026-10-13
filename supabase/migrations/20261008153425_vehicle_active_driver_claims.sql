-- Staged and OFF by default. No legacy row repair or inferred driver assignment.
-- Enable only after open pre-rollout vehicle shifts are explicitly resolved.
create table private.vehicle_usage_rollout (
  company_id uuid primary key references public.companies(id) on delete cascade,
  enabled boolean not null default false
);
revoke all on private.vehicle_usage_rollout from public, anon, authenticated;

create table public.vehicle_usage_claims (
  source_clock_in_id uuid primary key
    references public.attendance_verifications(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  driver_worker_id uuid not null references public.workers(id) on delete cascade,
  work_date date not null,
  started_at timestamptz not null,
  source_clock_out_id uuid unique
    references public.attendance_verifications(id) on delete set null,
  ended_at timestamptz,
  check (ended_at is null or ended_at >= started_at)
);
create unique index vehicle_usage_one_active_driver
  on public.vehicle_usage_claims(company_id, vehicle_id)
  where ended_at is null;
alter table public.vehicle_usage_claims enable row level security;
revoke all on public.vehicle_usage_claims from public, anon, authenticated;
grant select on public.vehicle_usage_claims to authenticated;
create policy vehicle_usage_claim_owner_or_attendance_manager
  on public.vehicle_usage_claims for select to authenticated using (
    exists(select 1 from public.company_members m
      where m.company_id=vehicle_usage_claims.company_id and m.user_id=(select auth.uid()))
    and (
      exists(select 1 from public.workers w
        where w.id=driver_worker_id and w.company_id=vehicle_usage_claims.company_id
          and w.user_id=(select auth.uid()))
      or private.has_company_feature(company_id,'can_manage_attendance')
    )
  );
create policy account_deletion_access_guard on public.vehicle_usage_claims
  as restrictive for all to authenticated
  using (private.account_access_allowed())
  with check (private.account_access_allowed());

-- Acquire the company serialization lock BEFORE attendance's vehicle/source
-- foreign keys. Even an OFF start must hold this through transaction commit so
-- activation cannot miss a previously uncommitted legacy start.
create function private.serialize_vehicle_verification()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();
begin
  if NEW.vehicle_id is null then return NEW; end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'vehicle attendance requires read committed isolation';
  end if;
  if not exists(select 1 from public.workers w where w.id=NEW.worker_id
      and w.company_id=NEW.company_id)
    or not exists(select 1 from public.vehicles v where v.id=NEW.vehicle_id
      and v.company_id=NEW.company_id) then
    raise exception 'vehicle attendance company is inconsistent';
  end if;
  -- Preserve trusted OFF migration/maintenance inserts with NULL auth.uid().
  -- Client NULL-auth writes still face existing RLS; ON's driver guard rejects
  -- NULL-auth inserts. No new bypass or grants are introduced here.
  if v_actor is not null and (not private.account_access_allowed() or not exists(
    select 1 from public.company_members m
      where m.company_id=NEW.company_id and m.user_id=v_actor
  )) then raise exception 'vehicle usage requires current company membership'; end if;
  -- Lock the FK parent before company serialization. Company deletion already
  -- holds this parent before cascades reach the rollout guard.
  perform 1 from public.companies c where c.id=NEW.company_id for key share;
  if not found then raise exception 'vehicle attendance company is unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||NEW.company_id::text,0));
  return NEW;
end $$;
revoke all on function private.serialize_vehicle_verification() from public,anon,authenticated;
create trigger vehicle_usage_serialize_before_verification before insert
  on public.attendance_verifications for each row
  execute function private.serialize_vehicle_verification();

create function private.enforce_vehicle_usage_claim()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := auth.uid();
  v_claim public.vehicle_usage_claims%rowtype;
  v_proxy boolean:=false;
  v_origin jsonb;
begin
  if NEW.vehicle_id is null then return NEW; end if;
  -- Existing companies keep their present behavior until explicit activation.
  perform 1 from private.vehicle_usage_rollout r
    where r.company_id=NEW.company_id and r.enabled;
  if not found then return NEW; end if;

  if v_actor is null or not private.account_access_allowed() or not exists (
    select 1 from public.company_members m
    where m.company_id=NEW.company_id and m.user_id=v_actor
  ) then raise exception 'vehicle usage requires current company membership'; end if;
  if not exists(select 1 from public.workers w
    where w.id=NEW.worker_id and w.company_id=NEW.company_id and w.status='active'
  ) then raise exception 'vehicle driver is unavailable'; end if;

  if NEW.event_type='clock_in' then
    -- Even an administrator cannot silently claim another worker as driver.
    if not exists(select 1 from public.workers w
      where w.id=NEW.worker_id and w.company_id=NEW.company_id and w.user_id=v_actor
    ) then raise exception 'vehicle clock in must be made by its driver'; end if;
    -- Attendance's vehicle FK already holds KEY SHARE. A key-changing lock
    -- would deadlock when two starts upgrade that lock simultaneously.
    perform 1 from public.vehicles v where v.id=NEW.vehicle_id
      and v.company_id=NEW.company_id and v.is_active for no key update;
    if not found then raise exception 'vehicle is unavailable'; end if;
    if NEW.work_date is null then raise exception 'vehicle shift needs canonical work date'; end if;
    insert into public.vehicle_usage_claims(
      source_clock_in_id,company_id,vehicle_id,driver_worker_id,work_date,started_at
    ) values(NEW.id,NEW.company_id,NEW.vehicle_id,NEW.worker_id,NEW.work_date,NEW.confirmed_at);
  elsif NEW.event_type='clock_out' then
    if NEW.source_clock_in_id is null then
      raise exception 'vehicle checkout needs explicit clock in';
    end if;
    select * into v_claim from public.vehicle_usage_claims c
      where c.source_clock_in_id=NEW.source_clock_in_id for update;
    if not found then
      -- No guessing a claim for pre-rollout shifts. Activation requires them
      -- resolved first; a missing claimed source is an actionable deployment gap.
      raise exception 'vehicle source predates rollout or is unavailable';
    end if;
    if row(v_claim.company_id,v_claim.vehicle_id,v_claim.driver_worker_id,v_claim.work_date)
      is distinct from row(NEW.company_id,NEW.vehicle_id,NEW.worker_id,NEW.work_date)
      or NEW.confirmed_at < v_claim.started_at then
      raise exception 'vehicle checkout source is inconsistent';
    end if;
    if not exists(select 1 from public.workers w
      where w.id=NEW.worker_id and w.company_id=NEW.company_id and w.user_id=v_actor
    ) and not private.has_company_feature(NEW.company_id,'can_manage_attendance') then
      -- #765's private scoped proxy writer is the only participant exception.
      -- Inspect optional staged columns as JSON so claims-only installations
      -- retain their exact schema. Direct client proxy origin is still rejected
      -- by #765's invoker BEFORE trigger, and never gains driver/meter authority.
      v_origin:=to_jsonb(NEW);
      if v_origin->>'evidence_origin'='team_proxy'
         and v_origin->>'proxy_actor_user_id'=v_actor::text
         and NEW.created_by=v_actor and NEW.verification_mode='manual'
         and NEW.site_id is not null and NEW.route_assignment_id is null
         and NEW.latitude is null and NEW.longitude is null and NEW.accuracy_m is null
         and NEW.distance_to_site_m is null and NEW.photo_storage_path is null
         and to_regclass('private.group_checkout_rollout') is not null
         and exists(select 1 from pg_catalog.pg_trigger t
           where t.tgrelid='public.attendance_verifications'::regclass
             and t.tgfoid=to_regprocedure('private.guard_group_checkout_origin()')
             and not t.tgisinternal and t.tgenabled in ('O','A'))
         and exists(select 1 from public.attendance_verifications own
           join public.workers w on w.id=own.worker_id and w.company_id=own.company_id
           where own.company_id=NEW.company_id and own.site_id=NEW.site_id
             and own.route_assignment_id is null and own.work_date=NEW.work_date
             and own.event_type='clock_in' and w.user_id=v_actor and w.status='active') then
        execute 'select exists(select 1 from private.group_checkout_rollout where company_id=$1 and enabled)'
          into v_proxy using NEW.company_id;
      end if;
      if not coalesce(v_proxy,false) then
        raise exception 'vehicle checkout requires driver, attendance manager or scoped actual participant';
      end if;
    end if;
    if v_claim.ended_at is not null then raise exception 'vehicle usage is already closed'; end if;
    update public.vehicle_usage_claims set ended_at=NEW.confirmed_at,source_clock_out_id=NEW.id
      where source_clock_in_id=NEW.source_clock_in_id;
  end if;
  return NEW;
end $$;
revoke all on function private.enforce_vehicle_usage_claim() from public, anon, authenticated;
create trigger vehicle_usage_claim_after_verification after insert
  on public.attendance_verifications for each row
  execute function private.enforce_vehicle_usage_claim();

-- Rollout cannot be disabled while it would strand an active claim.
create function private.guard_vehicle_usage_rollout()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'vehicle rollout changes require read committed isolation';
  end if;
  if TG_OP='UPDATE' and NEW.company_id is distinct from OLD.company_id then
    raise exception 'vehicle rollout company is immutable';
  end if;
  -- DELETE cascades may have removed the parent in this transaction. Preserve
  -- that existing path; ordinary calls acquire the parent before the advisory.
  perform 1 from public.companies c where c.id=
    (case when TG_OP='DELETE' then OLD.company_id else NEW.company_id end) for key share;
  perform pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||
    (case when TG_OP='DELETE' then OLD.company_id else NEW.company_id end)::text,0));
  -- VOLATILE trigger queries obtain a fresh READ COMMITTED snapshot after the
  -- lock wait, observing any committed OFF start before activation checks.
  if TG_OP='INSERT' or (not OLD.enabled and NEW.enabled) then
    if NEW.enabled and exists (
      select 1 from public.attendance_verifications a
      where a.company_id=NEW.company_id and a.event_type='clock_in'
        and a.vehicle_id is not null
        and not exists(select 1 from public.attendance_verifications o
          where o.source_clock_in_id=a.id and o.event_type='clock_out')
        and not exists(select 1 from public.vehicle_usage_claims c
          where c.source_clock_in_id=a.id)
    ) then raise exception 'resolve pre-rollout vehicle starts before enabling'; end if;
  end if;
  if TG_OP='DELETE' or (OLD.enabled and not NEW.enabled) then
    if exists(select 1 from public.vehicle_usage_claims c
      where c.company_id=OLD.company_id and c.ended_at is null) then
      raise exception 'close active vehicle usages before disabling rollout';
    end if;
  end if;
  if TG_OP='DELETE' then return OLD; end if;
  return NEW;
end $$;
revoke all on function private.guard_vehicle_usage_rollout() from public, anon, authenticated;
create trigger vehicle_usage_rollout_guard before insert or update or delete
  on private.vehicle_usage_rollout for each row execute function private.guard_vehicle_usage_rollout();
