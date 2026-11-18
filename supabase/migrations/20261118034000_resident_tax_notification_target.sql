begin;
set local lock_timeout='3s';
set local statement_timeout='25s';
create table private.resident_tax_reminder_receipts (
 company_id uuid not null references public.companies(id) on delete cascade,
 recipient_user_id uuid not null references auth.users(id) on delete cascade,
 tax_year integer not null check(tax_year between 2000 and 9999),
 phase text not null check(phase in ('month_before','week_before')),
 membership_created_at timestamptz not null,
 notification_id uuid unique,
 created_at timestamptz not null default clock_timestamp(),
 primary key(company_id,recipient_user_id,tax_year,phase)
);
alter table private.resident_tax_reminder_receipts enable row level security;
revoke all on private.resident_tax_reminder_receipts from public,anon,authenticated,service_role;

create function private.resident_tax_reminder_recipient(cid uuid,uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.company_members m join auth.users u on u.id=m.user_id
 where m.company_id=cid and m.user_id=uid and m.employment_ended_at is null and m.role::text in ('owner','admin','manager','viewer')
 and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp())
 and not exists(select 1 from private.account_deletion_access_restrictions r where r.user_id=uid)
 and (not exists(select 1 from public.workers w where w.company_id=cid and w.user_id=uid)
  or exists(select 1 from public.workers w where w.company_id=cid and w.user_id=uid and w.status::text='active'))
 and (m.role::text in ('owner','admin')
  or exists(select 1 from public.member_feature_permissions p where p.company_id=cid and p.user_id=uid and p.can_manage_payroll)
  or uid=any(private.payroll_approver_ids(cid))
  or exists(select 1 from public.payroll_access a where a.company_id=cid and a.user_id=uid and (a.can_view or a.can_edit))
  or exists(select 1 from private.professional_invites i where i.company_id=cid and i.claimed_by=uid and i.status='approved' and i.payroll_access<>'none')))
$$;
revoke all on function private.resident_tax_reminder_recipient(uuid,uuid) from public,anon,authenticated,service_role;

-- The annual receipt source is optional during staged deployment. Missing is incomplete.
-- No caller-selected function/schema or client-provided completion value is accepted.
create function private.resident_tax_reminder_year_complete(cid uuid,p_tax_year integer) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare result boolean;
begin
 if to_regprocedure('resident_tax_annual_private.year_complete(uuid,integer)') is null then return false;end if;
 if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('resident_tax_annual_private.year_complete(uuid,integer)')
  and p.prorettype='boolean'::regtype and p.prosecdef and p.proconfig=array['search_path=""']::text[]) then
  raise exception 'annual completion helper contract changed';end if;
 execute 'select resident_tax_annual_private.year_complete($1,$2)' into result using cid,p_tax_year;
 return result is true;
end $$;
revoke all on function private.resident_tax_reminder_year_complete(uuid,integer) from public,anon,authenticated,service_role;


create function private.resident_tax_reminder_target(p_notification_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();receipt private.resident_tax_reminder_receipts%rowtype;
begin
 if actor is null or private.account_access_allowed() is not true then raise exception 'notification unavailable' using errcode='42501';end if;
 select r.* into receipt from private.resident_tax_reminder_receipts r join public.app_notifications n on n.id=r.notification_id
 where r.notification_id=p_notification_id and r.recipient_user_id=actor and n.recipient_user_id=actor
 and n.company_id=r.company_id and n.kind='resident_tax_reminder' and n.action_key='payroll_settings' and n.action_id=r.company_id;
 if not found or private.resident_tax_reminder_recipient(receipt.company_id,actor) is not true or not exists(
  select 1 from public.company_members where company_id=receipt.company_id and user_id=actor and created_at=receipt.membership_created_at) then
  raise exception 'notification company or access changed' using errcode='42501';end if;
 return jsonb_build_object('version',1,'company_id',receipt.company_id,'tax_year',receipt.tax_year,'phase',receipt.phase,'complete',private.resident_tax_reminder_year_complete(receipt.company_id,receipt.tax_year));
end $$;
revoke all on function private.resident_tax_reminder_target(uuid) from public,anon,authenticated,service_role;
grant execute on function private.resident_tax_reminder_target(uuid) to authenticated;
create function public.resident_tax_reminder_target(p_notification_id uuid) returns jsonb language sql security invoker set search_path='' as $$
 select private.resident_tax_reminder_target(p_notification_id)$$;

revoke all on function public.resident_tax_reminder_target(uuid) from public,anon,authenticated,service_role;
grant execute on function public.resident_tax_reminder_target(uuid) to authenticated;

commit;
