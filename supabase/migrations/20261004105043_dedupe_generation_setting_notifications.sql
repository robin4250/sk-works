-- Mirrors production migration 20261004105043.
-- Keeps generation-setting alerts de-duplicated and resolves them automatically
-- when the relevant setting is completed.

create table if not exists public.generation_setting_issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  issue_key text not null,
  issue_type text not null,
  title text not null,
  body text not null,
  action_key text,
  action_id uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, issue_key)
);

alter table public.generation_setting_issues enable row level security;

drop policy if exists generation_setting_issues_management_select on public.generation_setting_issues;
create policy generation_setting_issues_management_select
on public.generation_setting_issues for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = generation_setting_issues.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

revoke insert, update, delete on public.generation_setting_issues from authenticated, anon;

create or replace function private.upsert_generation_setting_issue(
  cid uuid,
  p_issue_key text,
  p_issue_type text,
  p_title text,
  p_body text,
  p_action_key text default null,
  p_action_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_resolved timestamptz;
  existed boolean:=false;
  member record;
begin
  select true,resolved_at into existed,existing_resolved
  from public.generation_setting_issues
  where company_id=cid and issue_key=p_issue_key;

  insert into public.generation_setting_issues(
    company_id,issue_key,issue_type,title,body,action_key,action_id,resolved_at,updated_at
  )
  values(cid,p_issue_key,p_issue_type,p_title,p_body,p_action_key,p_action_id,null,now())
  on conflict(company_id,issue_key) do update
    set issue_type=excluded.issue_type,
        title=excluded.title,
        body=excluded.body,
        action_key=excluded.action_key,
        action_id=excluded.action_id,
        resolved_at=null,
        updated_at=now();

  if not existed or existing_resolved is not null then
    for member in
      select cm.user_id
      from public.company_members cm
      where cm.company_id=cid and cm.role::text in ('owner','admin','manager')
    loop
      perform private.enqueue_notification(
        cid,member.user_id,'warning',p_title,p_body,p_action_key,p_action_id
      );
    end loop;
  end if;
end;
$function$;

create or replace function private.refresh_generation_setting_issues(cid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  month_start date:=date_trunc('month',(current_timestamp at time zone 'Asia/Tokyo')::date)::date;
  active_keys text[]:='{}';
  r record;
  k text;
begin
  if cid is null then return; end if;

  for r in
    select distinct w.id,w.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    left join public.worker_payroll_settings ps on ps.company_id=a.company_id and ps.worker_id=a.worker_id
    where a.company_id=cid and a.work_date>=month_start and ps.worker_id is null
    order by w.name
  loop
    k:='payroll:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(
      cid,k,'payroll','給与明細の設定未入力',
      r.name||'：個別給与設定が未入力です',
      'payroll_settings',r.id
    );
  end loop;

  for r in
    select distinct s.id,s.name
    from public.attendance_entries a
    join public.sites s on s.id=a.site_id and s.company_id=a.company_id
    left join public.site_financial_settings fs on fs.site_id=s.id and fs.company_id=s.company_id
    where a.company_id=cid and a.work_date>=month_start
      and (
        fs.site_id is null or
        ((case when coalesce(fs.billing_unit_price_yen,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_square_meter_unit_price_yen,0)>0 and coalesce(fs.billing_square_meter_quantity,0)>0 then 1 else 0 end)
        +(case when coalesce(fs.billing_contract_amount_yen,0)>0 then 1 else 0 end))<>1
      )
    order by s.name
  loop
    k:='invoice-site:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(
      cid,k,'invoice','請求書の設定未入力',
      r.name||'：請求方式が未入力です',
      'admin_sites',r.id
    );
  end loop;

  if exists(
    select 1 from public.attendance_entries a
    where a.company_id=cid and a.work_date>=month_start
  ) and exists(
    select 1 from public.companies c
    where c.id=cid and (
      nullif(trim(coalesce(c.bank_name,'')),'') is null
      or nullif(trim(coalesce(c.bank_branch,'')),'') is null
      or nullif(trim(coalesce(c.bank_account_number,'')),'') is null
      or nullif(trim(coalesce(c.bank_account_holder,'')),'') is null
    )
  ) then
    k:='invoice-bank:'||cid::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(
      cid,k,'invoice','請求書の設定未入力',
      '請求書設定：振込口座が未入力です',
      'settings',cid
    );
  end if;

  for r in
    select distinct pc.id,pc.name
    from public.attendance_entries a
    join public.workers w on w.id=a.worker_id and w.company_id=a.company_id
    join public.partner_companies pc on pc.id=w.partner_company_id and pc.company_id=w.company_id
    left join public.partner_payment_settings pps on pps.company_id=pc.company_id and pps.partner_company_id=pc.id
    where a.company_id=cid and a.work_date>=month_start and pps.partner_company_id is null
    order by pc.name
  loop
    k:='payment:'||r.id::text;
    active_keys:=array_append(active_keys,k);
    perform private.upsert_generation_setting_issue(
      cid,k,'payment_certificate','支払証明書の設定未入力',
      r.name||'：支払証明書設定が未入力です',
      'payment_certificate_settings',r.id
    );
  end loop;

  update public.generation_setting_issues
  set resolved_at=now(),updated_at=now()
  where company_id=cid
    and resolved_at is null
    and not (issue_key=any(active_keys));
end;
$function$;

create or replace function private.refresh_generation_setting_issues_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare cid uuid;
begin
  cid:=case when tg_op='DELETE' then old.company_id else new.company_id end;
  perform private.refresh_generation_setting_issues(cid);

  if tg_op='UPDATE' and old.company_id is distinct from new.company_id then
    perform private.refresh_generation_setting_issues(old.company_id);
  end if;

  return null;
end;
$function$;

drop trigger if exists attendance_refresh_generation_setting_issues on public.attendance_entries;
create trigger attendance_refresh_generation_setting_issues
after insert or update or delete on public.attendance_entries
for each row execute function private.refresh_generation_setting_issues_trigger();

drop trigger if exists payroll_settings_refresh_generation_setting_issues on public.worker_payroll_settings;
create trigger payroll_settings_refresh_generation_setting_issues
after insert or update or delete on public.worker_payroll_settings
for each row execute function private.refresh_generation_setting_issues_trigger();

drop trigger if exists site_financial_refresh_generation_setting_issues on public.site_financial_settings;
create trigger site_financial_refresh_generation_setting_issues
after insert or update or delete on public.site_financial_settings
for each row execute function private.refresh_generation_setting_issues_trigger();

drop trigger if exists partner_payment_refresh_generation_setting_issues on public.partner_payment_settings;
create trigger partner_payment_refresh_generation_setting_issues
after insert or update or delete on public.partner_payment_settings
for each row execute function private.refresh_generation_setting_issues_trigger();

create or replace function private.company_refresh_generation_setting_issues_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.refresh_generation_setting_issues(new.id);
  return null;
end;
$function$;

drop trigger if exists company_refresh_generation_setting_issues on public.companies;
create trigger company_refresh_generation_setting_issues
after update of bank_name,bank_branch,bank_account_number,bank_account_holder on public.companies
for each row execute function private.company_refresh_generation_setting_issues_trigger();

create or replace function public.current_generation_setting_attention()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
 uid uuid:=auth.uid();
 cid uuid;
 role_text text;
 issues jsonb;
begin
 if uid is null then
   return jsonb_build_object('count',0,'issues','[]'::jsonb);
 end if;

 select cm.company_id,cm.role::text into cid,role_text
 from public.company_members cm
 where cm.user_id=uid
 limit 1;

 if cid is null or role_text not in ('owner','admin','manager') then
   return jsonb_build_object('count',0,'issues','[]'::jsonb);
 end if;

 select coalesce(jsonb_agg(jsonb_build_object(
   'type',g.issue_type,
   'key',g.issue_key,
   'message',g.body,
   'action_key',g.action_key,
   'action_id',g.action_id
 ) order by g.created_at),'[]'::jsonb)
 into issues
 from public.generation_setting_issues g
 where g.company_id=cid and g.resolved_at is null;

 return jsonb_build_object(
   'count',jsonb_array_length(issues),
   'issues',issues
 );
end;
$function$;

revoke execute on function public.current_generation_setting_attention() from public, anon;
grant execute on function public.current_generation_setting_attention() to authenticated;
