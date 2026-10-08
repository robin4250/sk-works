-- Stacked on staged vehicle claims. No existing claims receive guessed values.
alter table public.vehicle_usage_claims add column start_odometer_km numeric(12,1);
alter table public.vehicle_usage_claims add column claimed_at timestamptz;
create function private.snapshot_vehicle_claim_meter()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  select v.odometer_km into NEW.start_odometer_km from public.vehicles v
    where v.id=NEW.vehicle_id and v.company_id=NEW.company_id for no key update;
  if not found or NEW.start_odometer_km is null or NEW.start_odometer_km<0
    or NEW.start_odometer_km::text in ('NaN','Infinity','-Infinity') then
    raise exception 'vehicle baseline is unavailable';
  end if;
  NEW.claimed_at:=clock_timestamp();
  return NEW;
end $$;
revoke all on function private.snapshot_vehicle_claim_meter() from public,anon,authenticated;
create trigger vehicle_claim_meter_snapshot before insert on public.vehicle_usage_claims
  for each row execute function private.snapshot_vehicle_claim_meter();

-- IDs are snapshots, deliberately not cascading attendance/claim foreign keys:
-- an approved replacement of evidence must not erase a committed meter event.
create table public.vehicle_meter_events (
  id uuid primary key,
  source_clock_in_id uuid not null unique,
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null,
  driver_worker_id uuid not null,
  work_date date not null,
  previous_km numeric(12,1) not null check(previous_km>=0),
  current_km numeric(12,1) not null check(current_km>=0),
  distance_km numeric(12,1) not null check(distance_km>=0),
  manual_distance_km numeric(12,1),
  baseline_decreased boolean not null,
  recorded_by uuid not null,
  recorded_at timestamptz not null default now(),
  check ((baseline_decreased and current_km<previous_km and manual_distance_km is not null and manual_distance_km=distance_km)
    or (not baseline_decreased and current_km>=previous_km and manual_distance_km is null
      and distance_km=current_km-previous_km))
);
alter table public.vehicle_meter_events enable row level security;
revoke all on public.vehicle_meter_events from public,anon,authenticated;
grant select on public.vehicle_meter_events to authenticated;
create policy vehicle_meter_driver_or_existing_vehicle_manager on public.vehicle_meter_events
  for select to authenticated using (
    exists(select 1 from public.company_members m where m.company_id=vehicle_meter_events.company_id
      and m.user_id=(select auth.uid()) and (
        m.role::text in ('owner','admin','manager')
        or exists(select 1 from public.workers w where w.id=driver_worker_id
          and w.company_id=vehicle_meter_events.company_id and w.user_id=(select auth.uid()))
      ))
  );
create policy account_deletion_access_guard on public.vehicle_meter_events
  as restrictive for all to authenticated using(private.account_access_allowed())
  with check(private.account_access_allowed());

-- Durable pending administrator warning; no email or delivery claimed here.
create table private.vehicle_meter_notice_outbox (
  event_id uuid primary key references public.vehicle_meter_events(id) on delete cascade,
  company_id uuid not null,
  vehicle_id uuid not null,
  kind text not null check(kind='meter_baseline_decreased'),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  dispatched_at timestamptz
);
revoke all on private.vehicle_meter_notice_outbox from public,anon,authenticated;

create function private.record_vehicle_driver_meter(
  p_source_clock_in_id uuid,p_event_id uuid,p_current_km numeric,p_manual_distance_km numeric
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();
 v_claim public.vehicle_usage_claims%rowtype;
 v_identity public.vehicle_usage_claims%rowtype;
 v_event public.vehicle_meter_events%rowtype;
 v_current numeric;
 v_decreased boolean;
 v_distance numeric;
begin
 if v_actor is null or not private.account_access_allowed() then raise exception 'ログインが必要です'; end if;
 if p_event_id is null or p_current_km is null or p_current_km<0
   or p_current_km::text in ('NaN','Infinity','-Infinity') or p_current_km<>round(p_current_km,1)
   or (p_manual_distance_km is not null and (p_manual_distance_km<0
     or p_manual_distance_km::text in ('NaN','Infinity','-Infinity')
     or p_manual_distance_km<>round(p_manual_distance_km,1))) then
   raise exception 'メーター値と移動距離は0以上・小数1桁の数値を入力してください';
 end if;
 if current_setting('transaction_isolation')<>'read committed' then
   raise exception 'vehicle meter registration requires read committed isolation';
 end if;
 -- Read identity before locking, then company -> vehicle -> claim order, matching
 -- starts and vehicle deletion cascades. Recheck the locked claim below.
 select * into v_claim from public.vehicle_usage_claims c
   where c.source_clock_in_id=p_source_clock_in_id;
 if not found or not exists(select 1 from public.company_members m
     where m.company_id=v_claim.company_id and m.user_id=v_actor)
   or not exists(select 1 from public.workers w where w.id=v_claim.driver_worker_id
     and w.company_id=v_claim.company_id and w.user_id=v_actor and w.status='active') then
   raise exception '車両の運転手本人だけがメーターを登録できます';
 end if;
 v_identity:=v_claim;
 perform 1 from public.companies c where c.id=v_identity.company_id for key share;
 if not found then raise exception '車両の会社を確認できません'; end if;
 perform pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||v_identity.company_id::text,0));
 perform 1 from public.vehicles v
   where v.id=v_claim.vehicle_id and v.company_id=v_claim.company_id for no key update;
 if not found then raise exception '車両を確認できません'; end if;
 -- Claim identity may have changed through an administrator's deletion cascade.
 select * into v_claim from public.vehicle_usage_claims c
   where c.source_clock_in_id=p_source_clock_in_id for update;
 if not found or row(v_claim.company_id,v_claim.vehicle_id,v_claim.driver_worker_id,
      v_claim.work_date,v_claim.started_at,v_claim.claimed_at)
      is distinct from row(v_identity.company_id,v_identity.vehicle_id,v_identity.driver_worker_id,
      v_identity.work_date,v_identity.started_at,v_identity.claimed_at)
   or not exists(select 1 from public.company_members m
     where m.company_id=v_claim.company_id and m.user_id=v_actor)
   or not exists(select 1 from public.workers w where w.id=v_claim.driver_worker_id
     and w.company_id=v_claim.company_id and w.user_id=v_actor and w.status='active') then
   raise exception '車両の運転手本人だけがメーターを登録できます';
 end if;
 perform 1 from private.vehicle_usage_rollout r
   where r.company_id=v_claim.company_id and r.enabled;
 if not found then raise exception '車両連携はまだ有効ではありません'; end if;
 -- Retry must reuse the committed snapshot, before reading mutable vehicle data.
 select * into v_event from public.vehicle_meter_events e
   where e.source_clock_in_id=p_source_clock_in_id;
 if found then
   if v_event.id<>p_event_id or v_event.current_km<>p_current_km
     or v_event.manual_distance_km is distinct from p_manual_distance_km then
     raise exception '登録済みのメーター変更は管理者へ修正を申請してください';
   end if;
   return to_jsonb(v_event);
 end if;
 if v_claim.ended_at is null then raise exception '退勤後に最終メーターを登録してください'; end if;
 if v_claim.start_odometer_km is null or v_claim.claimed_at is null then
   raise exception '導入前の車両勤務には基準値がありません。管理者へ確認してください';
 end if;
 select v.odometer_km into v_current from public.vehicles v
   where v.id=v_claim.vehicle_id and v.company_id=v_claim.company_id for no key update;
 if not found then raise exception '車両を確認できません'; end if;
 if v_current is distinct from v_claim.start_odometer_km or exists(
   select 1 from public.vehicle_usage_claims other where other.vehicle_id=v_claim.vehicle_id
     and other.company_id=v_claim.company_id and other.source_clock_in_id<>v_claim.source_clock_in_id
     and other.claimed_at>=v_claim.claimed_at
 ) then raise exception '後続の車両利用または基準値変更があります。管理者へ修正を申請してください'; end if;
 v_decreased:=p_current_km<v_claim.start_odometer_km;
 if v_decreased and p_manual_distance_km is null then
   raise exception 'メーター数値が減っています。その日の移動距離を手入力してください';
 end if;
 if not v_decreased and p_manual_distance_km is not null then
   raise exception '通常の走行距離はメーター差分で計算します';
 end if;
 v_distance:=case when v_decreased then p_manual_distance_km else p_current_km-v_claim.start_odometer_km end;
 insert into public.vehicle_meter_events(id,source_clock_in_id,company_id,vehicle_id,
   driver_worker_id,work_date,previous_km,current_km,distance_km,manual_distance_km,
   baseline_decreased,recorded_by)
 values(p_event_id,v_claim.source_clock_in_id,v_claim.company_id,v_claim.vehicle_id,
   v_claim.driver_worker_id,v_claim.work_date,v_claim.start_odometer_km,p_current_km,v_distance,
   p_manual_distance_km,v_decreased,v_actor) returning * into v_event;
 update public.vehicles set odometer_km=p_current_km,updated_by=v_actor,updated_at=now()
   where id=v_claim.vehicle_id and company_id=v_claim.company_id;
 if v_decreased then
   insert into private.vehicle_meter_notice_outbox(event_id,company_id,vehicle_id,kind,payload)
   values(v_event.id,v_claim.company_id,v_claim.vehicle_id,'meter_baseline_decreased',
     to_jsonb(v_event)||jsonb_build_object('message','数値の大幅な変更があります。前回距離の変更を確認してください'));
 end if;
 return to_jsonb(v_event);
end $$;
revoke all on function private.record_vehicle_driver_meter(uuid,uuid,numeric,numeric) from public,anon,authenticated;
create function public.record_vehicle_driver_meter(
 p_source_clock_in_id uuid,p_event_id uuid,p_current_km numeric,p_manual_distance_km numeric default null
) returns jsonb language sql security definer set search_path='' as $$
 select private.record_vehicle_driver_meter(p_source_clock_in_id,p_event_id,p_current_km,p_manual_distance_km)
$$;
revoke all on function public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric) from public,anon;
grant execute on function public.record_vehicle_driver_meter(uuid,uuid,numeric,numeric) to authenticated;

-- Preserve the old signature and exact OFF implementation. ON vehicle writes
-- must use the immutable driver RPC instead of the old group-writer loop.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)'::regprocedure);
 definition:=replace(definition,'private.save_daily_report_vehicle_usage(',
   'private.save_daily_report_vehicle_usage_before_meter_snapshots(');
 execute definition;
end $$;
revoke all on function private.save_daily_report_vehicle_usage_before_meter_snapshots(uuid,uuid,uuid,uuid,numeric)
 from public,anon,authenticated;
create or replace function private.save_daily_report_vehicle_usage(
 p_report_id uuid,p_worker_id uuid,p_vehicle_id uuid,p_route_assignment_id uuid,p_odometer_km numeric
) returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.daily_reports d join private.vehicle_usage_rollout r on r.company_id=d.company_id
   where d.id=p_report_id and r.enabled) and (p_vehicle_id is not null or exists(
     select 1 from public.daily_report_workers w where w.report_id=p_report_id
       and w.worker_id=p_worker_id and w.vehicle_id is not null
   )) then raise exception '車両メーターは運転手本人の登録画面から保存してください'; end if;
 perform private.save_daily_report_vehicle_usage_before_meter_snapshots(
   p_report_id,p_worker_id,p_vehicle_id,p_route_assignment_id,p_odometer_km);
end $$;
