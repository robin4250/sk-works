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

create function private.enforce_vehicle_usage_claim()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := auth.uid();
  v_claim public.vehicle_usage_claims%rowtype;
begin
  if NEW.vehicle_id is null then return NEW; end if;
  -- Existing companies keep their present behavior until explicit activation.
  perform 1 from private.vehicle_usage_rollout r
    where r.company_id=NEW.company_id and r.enabled for share;
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
    perform 1 from public.vehicles v where v.id=NEW.vehicle_id
      and v.company_id=NEW.company_id and v.is_active for update;
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
      raise exception 'vehicle checkout requires driver or existing attendance manager';
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
