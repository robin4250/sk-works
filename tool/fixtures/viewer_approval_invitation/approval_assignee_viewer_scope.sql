-- Selected approvers gain only approval access; existing company selections remain unchanged.

create or replace function public.worker_personnel_approver_rows()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); cid uuid; role_text text;
begin
  if not private.account_access_allowed() then raise exception 'authentication required'; end if;
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm where cm.user_id=uid limit 1;
  if cid is null then raise exception '会社への所属が必要です'; end if;
  if role_text not in ('owner','admin') then
    raise exception '承認者設定は管理者のみ利用できます';
  end if;
  return jsonb_build_object(
    'selected',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',a.user_id,'position',a.position,
        'name',coalesce(w.name,cm.user_id::text)
      ) order by a.position)
      from public.worker_personnel_approvers a
      join public.company_members cm
        on cm.company_id=a.company_id and cm.user_id=a.user_id
      left join public.workers w
        on w.company_id=cm.company_id and w.user_id=cm.user_id
      where a.company_id=cid
    ),'[]'::jsonb),
    'candidates',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',cm.user_id,'name',coalesce(w.name,cm.user_id::text),
        'role',cm.role::text
      ) order by coalesce(w.name,cm.user_id::text))
      from public.company_members cm
      left join public.workers w
        on w.company_id=cm.company_id and w.user_id=cm.user_id
      where cm.company_id=cid
        and cm.role::text in ('owner','admin','manager','viewer')
    ),'[]'::jsonb)
  );
end
$$;

create or replace function public.set_worker_personnel_approvers(p_user_ids uuid[])
returns void
language plpgsql security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); cid uuid; role_text text;
  candidate uuid; pos integer:=0;
begin
  if not private.account_access_allowed() then raise exception 'authentication required'; end if;
  select cm.company_id,cm.role::text into cid,role_text
  from public.company_members cm where cm.user_id=uid limit 1;
  if cid is null or role_text not in ('owner','admin') then
    raise exception '承認者設定は管理者のみ変更できます';
  end if;
  if coalesce(array_length(p_user_ids,1),0) not between 1 and 3 then
    raise exception '承認者は1〜3名で設定してください';
  end if;
  if (select count(distinct x) from unnest(p_user_ids) x)
     <> array_length(p_user_ids,1) then
    raise exception '同じ承認者を重複して登録できません';
  end if;
  foreach candidate in array p_user_ids loop
    if not exists(
      select 1 from public.company_members cm
      where cm.company_id=cid and cm.user_id=candidate
        and cm.role::text in ('owner','admin','manager','viewer')
    ) then
      raise exception '承認者は自社の管理者・サブ管理者・閲覧者から選択してください';
    end if;
  end loop;
  delete from public.worker_personnel_approvers where company_id=cid;
  foreach candidate in array p_user_ids loop
    pos:=pos+1;
    insert into public.worker_personnel_approvers(company_id,user_id,position)
    values(cid,candidate,pos);
  end loop;
end
$$;

create or replace function public.company_approval_assignee_rows()
returns table(
  user_id uuid,
  display_name text,
  role text,
  is_assignee boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
begin
  if not private.account_access_allowed() then raise exception 'authentication required'; end if;
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  return query
  select
    cm.user_id,
    coalesce(up.display_name, 'SKOユーザー')::text,
    cm.role::text,
    (caa.user_id is not null)
  from public.company_members cm
  left join public.user_profiles up on up.user_id = cm.user_id
  left join public.company_approval_assignees caa
    on caa.company_id = cm.company_id
   and caa.user_id = cm.user_id
  where cm.company_id = v_company_id
    and cm.role::text in ('owner','admin','manager','viewer')
  order by
    (caa.user_id is not null) desc,
    coalesce(up.display_name, 'SKOユーザー');
end;
$$;

create or replace function public.set_company_approval_assignee(
  p_user_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_count integer;
begin
  if not private.account_access_allowed() then raise exception 'authentication required'; end if;
  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_actor
    and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text
  into v_target_role
  from public.company_members cm
  where cm.company_id = v_company_id
    and cm.user_id = p_user_id
  limit 1;

  if v_target_role is null then
    raise exception 'target user is not in company';
  end if;

  if p_enabled and v_target_role not in ('owner','admin','manager','viewer') then
    raise exception 'approval assignee must be an eligible company member';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_company_id::text, 0));

  select count(*)
  into v_count
  from public.company_approval_assignees
  where company_id = v_company_id;

  if p_enabled then
    if exists (
      select 1 from public.company_approval_assignees
      where company_id = v_company_id and user_id = p_user_id
    ) then
      return;
    end if;

    if v_count >= 3 then
      raise exception 'approval_assignee_limit_reached';
    end if;

    insert into public.company_approval_assignees(
      company_id, user_id, created_by
    )
    values(v_company_id, p_user_id, v_actor);
    return;
  end if;

  if not exists (
    select 1 from public.company_approval_assignees
    where company_id = v_company_id and user_id = p_user_id
  ) then
    return;
  end if;

  if v_count <= 1 then
    raise exception 'at_least_one_approval_assignee_required';
  end if;

  delete from public.company_approval_assignees
  where company_id = v_company_id
    and user_id = p_user_id;
end;
$$;

create or replace function private.is_company_approval_assignee(p_company_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.account_access_allowed() and exists(select 1 from public.company_approval_assignees a
 join public.company_members cm on cm.company_id=a.company_id and cm.user_id=a.user_id
 where a.company_id=p_company_id and a.user_id=auth.uid()
 and cm.role::text in ('owner','admin','manager','viewer'))
$$;
create or replace function private.is_worker_personnel_approver(p_company_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.account_access_allowed() and exists(select 1 from public.worker_personnel_approvers a
 join public.company_members cm on cm.company_id=a.company_id and cm.user_id=a.user_id
 where a.company_id=p_company_id and a.user_id=auth.uid()
 and cm.role::text in ('owner','admin','manager','viewer'))
$$;
revoke all on function private.is_company_approval_assignee(uuid) from public,anon;
revoke all on function private.is_worker_personnel_approver(uuid) from public,anon;
grant execute on function private.is_company_approval_assignee(uuid) to authenticated;
grant execute on function private.is_worker_personnel_approver(uuid) to authenticated;

alter policy "requester or authorized approver can read edit requests"
on public.daily_report_edit_requests to authenticated
using (requested_by=auth.uid() or private.is_company_approval_assignee(company_id));
alter policy "requester or authorized approver can read approvals"
on public.daily_report_edit_approvals to authenticated
using (exists(select 1 from public.daily_report_edit_requests r
 where r.id=request_id and (r.requested_by=auth.uid() or private.is_company_approval_assignee(r.company_id))));


create or replace function public.decide_daily_report_edit(
  p_request_id uuid,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_requested_by uuid;
  v_status text;
  v_assignee_count integer;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision';
  end if;

  select req.company_id, req.requested_by, req.status
  into v_company_id, v_requested_by, v_status
  from public.daily_report_edit_requests req
  where req.id = p_request_id
  for update;

  if v_company_id is null or v_status <> 'pending' then
    raise exception 'pending request not found';
  end if;

  if not private.is_company_approval_assignee(v_company_id) then
    raise exception 'approval assignee permission required';
  end if;

  select count(*) into v_assignee_count
  from public.company_approval_assignees
  where company_id = v_company_id;

  -- Multi-person companies keep separation of requester/approver.
  -- A sole proprietor may self-approve only when they are the company's
  -- single configured approval assignee.
  if v_requested_by = v_user_id and v_assignee_count > 1 then
    raise exception 'requester cannot approve own request';
  end if;

  insert into public.daily_report_edit_approvals(
    request_id,
    approver_user_id,
    decision
  )
  values(
    p_request_id,
    v_user_id,
    p_decision
  )
  on conflict(request_id, approver_user_id) do update
  set decision = excluded.decision,
      decided_at = now();

  if p_decision = 'reject' then
    update public.daily_report_edit_requests
    set status = 'rejected',
        resolved_at = now()
    where id = p_request_id;

    perform private.enqueue_notification(
      v_company_id,
      v_requested_by,
      'warning',
      '日報修正申請が却下されました',
      '確定済み日報の修正申請が却下されました。',
      'daily_report_edit_request',
      p_request_id
    );
    return 'rejected';
  end if;

  update public.daily_report_edit_requests
  set status = 'approved',
      resolved_at = now(),
      approvals_required = 1
  where id = p_request_id;

  perform private.enqueue_notification(
    v_company_id,
    v_requested_by,
    'approval',
    '日報を編集できます',
    '設定された承認担当者の承認が完了しました。日報を開いて編集してください。',
    'daily_report_edit_request',
    p_request_id
  );

  return 'approved';
end;
$$;

-- Only initial company membership seeds one administrator. No backfill or shrink.
create or replace function private.seed_initial_worker_personnel_approver()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if NEW.role::text in ('owner','admin')
 and (select count(*) from public.company_members where company_id=NEW.company_id)=1
 and not exists(select 1 from public.worker_personnel_approvers where company_id=NEW.company_id) then
  insert into public.worker_personnel_approvers(company_id,user_id,position)
  values(NEW.company_id,NEW.user_id,1) on conflict do nothing;
 end if;
 return NEW;
end $$;
revoke all on function private.seed_initial_worker_personnel_approver() from public,anon,authenticated;
create trigger initial_worker_personnel_approver after insert on public.company_members
 for each row execute function private.seed_initial_worker_personnel_approver();


create or replace function public.set_member_feature_permissions(
  p_user_id uuid,
  p_role text,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_company_id uuid;
  v_target_role text;
  v_can_manage_attendance boolean;
  v_can_manage_people boolean;
  v_can_manage_partner_chat boolean;
  v_can_manage_vehicles boolean;
  v_can_manage_routes boolean;
begin
  if not private.account_access_allowed() then raise exception 'authentication required'; end if;
  select cm.company_id into v_company_id
  from public.company_members cm
  where cm.user_id=v_actor and cm.role::text in ('owner','admin')
  limit 1;

  if v_company_id is null then
    raise exception 'owner or admin permission required';
  end if;

  select cm.role::text into v_target_role
  from public.company_members cm
  where cm.company_id=v_company_id and cm.user_id=p_user_id
  limit 1;

  if v_target_role is null then raise exception 'target user is not in company'; end if;
  if v_target_role='owner' then raise exception 'owner role cannot be changed'; end if;
  if p_role not in ('admin','manager','viewer') then raise exception 'invalid role'; end if;

  -- Approval selection is independent of management role.
  update public.company_members
  set role=p_role
  where company_id=v_company_id and user_id=p_user_id;

  if p_role='admin' then
    delete from public.member_feature_permissions
    where company_id=v_company_id and user_id=p_user_id;
    return;
  end if;

  v_can_manage_attendance :=
    coalesce((p_permissions->>'can_manage_attendance')::boolean,false);
  v_can_manage_people :=
    coalesce((p_permissions->>'can_manage_people')::boolean,false);
  v_can_manage_partner_chat :=
    coalesce((p_permissions->>'can_manage_partner_chat')::boolean,false);
  v_can_manage_vehicles :=
    coalesce((p_permissions->>'can_manage_vehicles')::boolean,false);
  v_can_manage_routes :=
    coalesce((p_permissions->>'can_manage_routes')::boolean,false);

  insert into public.member_feature_permissions(
    company_id,user_id,
    can_approve_daily_report_edits,
    can_manage_attendance,
    can_manage_people,
    can_view_invoices,
    can_manage_invoices,
    can_view_admin_site_data,
    can_manage_admin_site_data,
    can_manage_payroll,
    can_manage_partner_chat,
    can_manage_vehicles,
    can_manage_routes,
    updated_by,updated_at
  ) values(
    v_company_id,p_user_id,
    false,
    v_can_manage_attendance,
    v_can_manage_people,
    false,false,false,false,false,
    v_can_manage_partner_chat,
    v_can_manage_vehicles,
    v_can_manage_routes,
    v_actor,now()
  )
  on conflict(company_id,user_id) do update
  set can_approve_daily_report_edits=false,
      can_manage_attendance=excluded.can_manage_attendance,
      can_manage_people=excluded.can_manage_people,
      can_view_invoices=false,
      can_manage_invoices=false,
      can_view_admin_site_data=false,
      can_manage_admin_site_data=false,
      can_manage_payroll=false,
      can_manage_partner_chat=excluded.can_manage_partner_chat,
      can_manage_vehicles=excluded.can_manage_vehicles,
      can_manage_routes=excluded.can_manage_routes,
      updated_by=v_actor,
      updated_at=now();
end;
$$;
