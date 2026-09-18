create table if not exists public.line_binding_claims (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  communication_group_id uuid not null references public.communication_groups(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  claim_code text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'cancelled', 'expired')),
  expires_at timestamptz not null,
  verified_line_group_id text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz
);

create unique index if not exists line_binding_claims_one_pending_per_group
  on public.line_binding_claims(communication_group_id)
  where status = 'pending';

create index if not exists line_binding_claims_company_status_idx
  on public.line_binding_claims(company_id, status, expires_at);

create table if not exists public.line_binding_audit (
  id uuid primary key default gen_random_uuid(),
  binding_id uuid references public.line_group_bindings(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  communication_group_id uuid not null references public.communication_groups(id) on delete cascade,
  line_group_id text not null,
  action text not null check (action in ('activated', 'disabled')),
  actor_user_id uuid references auth.users(id) on delete set null,
  source text not null check (source in ('sko_admin', 'line_claim')),
  occurred_at timestamptz not null default now()
);

create index if not exists line_binding_audit_company_time_idx
  on public.line_binding_audit(company_id, occurred_at desc);

create unique index if not exists line_group_bindings_one_active_per_communication_group
  on public.line_group_bindings(communication_group_id)
  where status = 'active' and communication_group_id is not null;

alter table public.line_binding_claims enable row level security;
alter table public.line_binding_audit enable row level security;

drop policy if exists "owners and admins can read line binding claims"
  on public.line_binding_claims;
create policy "owners and admins can read line binding claims"
on public.line_binding_claims
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_binding_claims.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

drop policy if exists "owners and admins can read line binding audit"
  on public.line_binding_audit;
create policy "owners and admins can read line binding audit"
on public.line_binding_audit
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_binding_audit.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner', 'admin')
  )
);

create or replace function public.begin_line_group_claim(
  p_communication_group_id uuid
)
returns table (
  claim_code text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_code text;
  v_expires_at timestamptz := now() + interval '15 minutes';
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cg.company_id
    into v_company_id
  from public.communication_groups cg
  where cg.id = p_communication_group_id;

  if v_company_id is null then
    raise exception 'communication group not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_company_id
      and cm.user_id = v_user_id
      and cm.role::text in ('owner', 'admin')
  ) then
    raise exception 'owner or admin role required';
  end if;

  if exists (
    select 1
    from public.line_group_bindings lgb
    where lgb.communication_group_id = p_communication_group_id
      and lgb.status = 'active'
  ) then
    raise exception 'communication group already has an active LINE binding';
  end if;

  update public.line_binding_claims
  set status = 'cancelled',
      cancelled_at = now()
  where communication_group_id = p_communication_group_id
    and status = 'pending';

  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1 from public.line_binding_claims c where c.claim_code = v_code
    );
  end loop;

  insert into public.line_binding_claims (
    company_id,
    communication_group_id,
    requested_by,
    claim_code,
    expires_at
  )
  values (
    v_company_id,
    p_communication_group_id,
    v_user_id,
    v_code,
    v_expires_at
  );

  return query select v_code, v_expires_at;
end;
$$;

revoke all on function public.begin_line_group_claim(uuid) from public;
grant execute on function public.begin_line_group_claim(uuid) to authenticated;

create or replace function public.complete_line_group_claim_for_line(
  p_claim_code text,
  p_line_group_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim public.line_binding_claims%rowtype;
  v_binding_id uuid;
  v_existing public.line_group_bindings%rowtype;
begin
  if nullif(trim(p_claim_code), '') is null
     or nullif(trim(p_line_group_id), '') is null then
    raise exception 'claim code and LINE group are required';
  end if;

  select *
    into v_claim
  from public.line_binding_claims
  where claim_code = upper(trim(p_claim_code))
    and status = 'pending'
  for update;

  if not found then
    raise exception 'claim code is invalid or already used';
  end if;

  if v_claim.expires_at <= now() then
    update public.line_binding_claims
    set status = 'expired'
    where id = v_claim.id;
    raise exception 'claim code expired';
  end if;

  select *
    into v_existing
  from public.line_group_bindings
  where line_group_id = trim(p_line_group_id)
  for update;

  if found then
    if v_existing.status = 'active'
       and (
         v_existing.company_id is distinct from v_claim.company_id
         or v_existing.communication_group_id is distinct from v_claim.communication_group_id
       ) then
      raise exception 'LINE group is already claimed';
    end if;

    update public.line_group_bindings
    set company_id = v_claim.company_id,
        communication_group_id = v_claim.communication_group_id,
        status = 'active',
        updated_at = now()
    where id = v_existing.id
    returning id into v_binding_id;
  else
    insert into public.line_group_bindings (
      line_group_id,
      company_id,
      communication_group_id,
      status
    )
    values (
      trim(p_line_group_id),
      v_claim.company_id,
      v_claim.communication_group_id,
      'active'
    )
    returning id into v_binding_id;
  end if;

  update public.line_binding_claims
  set status = 'completed',
      verified_line_group_id = trim(p_line_group_id),
      completed_at = now()
  where id = v_claim.id;

  insert into public.line_binding_audit (
    binding_id,
    company_id,
    communication_group_id,
    line_group_id,
    action,
    actor_user_id,
    source
  )
  values (
    v_binding_id,
    v_claim.company_id,
    v_claim.communication_group_id,
    trim(p_line_group_id),
    'activated',
    v_claim.requested_by,
    'line_claim'
  );

  return v_binding_id;
end;
$$;

revoke all on function public.complete_line_group_claim_for_line(text, text) from public;
revoke all on function public.complete_line_group_claim_for_line(text, text) from authenticated;
grant execute on function public.complete_line_group_claim_for_line(text, text) to service_role;

create or replace function public.disable_line_group_binding(
  p_binding_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_binding public.line_group_bindings%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select *
    into v_binding
  from public.line_group_bindings
  where id = p_binding_id
  for update;

  if not found or v_binding.company_id is null or v_binding.communication_group_id is null then
    raise exception 'LINE binding not found';
  end if;

  if not exists (
    select 1
    from public.company_members cm
    where cm.company_id = v_binding.company_id
      and cm.user_id = v_user_id
      and cm.role::text in ('owner', 'admin')
  ) then
    raise exception 'owner or admin role required';
  end if;

  if v_binding.status <> 'active' then
    return;
  end if;

  update public.line_group_bindings
  set status = 'disabled',
      updated_at = now()
  where id = v_binding.id;

  insert into public.line_binding_audit (
    binding_id,
    company_id,
    communication_group_id,
    line_group_id,
    action,
    actor_user_id,
    source
  )
  values (
    v_binding.id,
    v_binding.company_id,
    v_binding.communication_group_id,
    v_binding.line_group_id,
    'disabled',
    v_user_id,
    'sko_admin'
  );
end;
$$;

revoke all on function public.disable_line_group_binding(uuid) from public;
grant execute on function public.disable_line_group_binding(uuid) to authenticated;
