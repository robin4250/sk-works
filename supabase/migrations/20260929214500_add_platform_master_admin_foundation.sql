create table if not exists public.platform_master_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  provisioned_at timestamptz not null default now(),
  provisioned_note text,
  disabled_at timestamptz
);

comment on table public.platform_master_admins is
  'SKO全体運営用のマスター管理者。通常の会社管理者からは変更できない。';

alter table public.platform_master_admins enable row level security;

revoke all on public.platform_master_admins from public, anon, authenticated;

create or replace function public.is_platform_master_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.platform_master_admins pma
    where pma.user_id = auth.uid()
      and pma.disabled_at is null
  );
$$;

revoke execute on function public.is_platform_master_admin()
  from public, anon;
grant execute on function public.is_platform_master_admin()
  to authenticated;

create table if not exists public.platform_master_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_kind text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists platform_master_audit_created_idx
  on public.platform_master_audit_log(created_at desc);

alter table public.platform_master_audit_log enable row level security;

revoke all on public.platform_master_audit_log
  from public, anon, authenticated;

drop policy if exists "master admins can read platform audit"
  on public.platform_master_audit_log;
create policy "master admins can read platform audit"
on public.platform_master_audit_log
for select
to authenticated
using (public.is_platform_master_admin());

grant select on public.platform_master_audit_log to authenticated;

create or replace function public.platform_master_admin_status()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'is_master_admin',
    public.is_platform_master_admin()
  );
$$;

revoke execute on function public.platform_master_admin_status()
  from public, anon;
grant execute on function public.platform_master_admin_status()
  to authenticated;

-- Intentionally no authenticated INSERT/UPDATE/DELETE policy and no
-- client-facing grant/revoke RPC. Provisioning remains a server-side
-- operational action so company owners/admins cannot elevate themselves.
