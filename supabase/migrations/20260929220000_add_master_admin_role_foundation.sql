create table if not exists private.master_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  disabled_at timestamptz,
  note text,
  constraint master_admin_enabled_disabled_consistency
    check (
      (enabled and disabled_at is null)
      or
      (not enabled and disabled_at is not null)
    )
);

create table if not exists private.master_admin_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists master_admin_audit_created_idx
  on private.master_admin_audit_log(created_at desc);

revoke all on private.master_admins from public, anon, authenticated;
revoke all on private.master_admin_audit_log from public, anon, authenticated;

create or replace function public.is_current_user_master_admin()
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from private.master_admins ma
    where ma.user_id = auth.uid()
      and ma.enabled
  );
$$;

create or replace function public.current_master_admin_status()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select jsonb_build_object(
    'is_master_admin',
    public.is_current_user_master_admin()
  );
$$;

revoke execute on function public.is_current_user_master_admin()
  from public, anon;
revoke execute on function public.current_master_admin_status()
  from public, anon;

grant execute on function public.is_current_user_master_admin()
  to authenticated;
grant execute on function public.current_master_admin_status()
  to authenticated;

comment on table private.master_admins is
  'SKO全体運営のマスター管理者。通常の会社管理者UI/RPCからは変更不可。';
comment on table private.master_admin_audit_log is
  'マスター管理者の重要操作を記録する監査ログ。';
