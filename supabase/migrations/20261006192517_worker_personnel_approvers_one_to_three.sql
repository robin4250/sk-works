-- Configurable 1-3 approvers for employee personnel changes.
create table if not exists public.worker_personnel_approvers (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  position integer not null check (position between 1 and 3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id,user_id),
  unique (company_id,position)
);
alter table public.worker_personnel_approvers enable row level security;
revoke all on public.worker_personnel_approvers from anon, authenticated;

alter table public.worker_personnel_change_requests
  add column if not exists required_approvals integer not null default 1
  check (required_approvals between 1 and 3);

insert into public.worker_personnel_approvers(company_id,user_id,position)
select company_id,user_id,rn
from (
  select a.company_id,a.user_id,
         row_number() over(partition by a.company_id order by a.created_at,a.user_id)::integer rn
  from public.company_approval_assignees a
) q
where rn between 1 and 3
on conflict do nothing;

insert into public.worker_personnel_approvers(company_id,user_id,position)
select x.company_id,x.user_id,x.position
from (
  select cm.company_id,cm.user_id,
         row_number() over(partition by cm.company_id order by
           case cm.role::text when 'owner' then 0 else 1 end, cm.user_id
         )::integer position
  from public.company_members cm
  where cm.role::text in ('owner','admin')
    and not exists (
      select 1 from public.worker_personnel_approvers a
      where a.company_id=cm.company_id
    )
) x
where x.position between 1 and 3
on conflict do nothing;

create or replace function private.is_worker_personnel_approver(p_company_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from public.worker_personnel_approvers a
    where a.company_id=p_company_id and a.user_id=auth.uid()
  )
$$;

create or replace function public.worker_personnel_approver_rows()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
  uid uuid:=auth.uid(); cid uuid; role_text text;
begin
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
        and cm.role::text in ('owner','admin','manager')
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
        and cm.role::text in ('owner','admin','manager')
    ) then
      raise exception '承認者は自社の管理者・サブ管理者から選択してください';
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

create or replace function public.save_worker_personnel_profile(
  p_worker_id uuid,p_payload jsonb
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_company uuid; v_existing boolean; v_request uuid; v_current jsonb;
  v_actor uuid:=auth.uid(); v_required integer;
begin
  if v_actor is null then raise exception 'ログインが必要です'; end if;
  if not private.can_edit_worker_personnel(p_worker_id) then
    raise exception '社員個人情報を変更する権限がありません';
  end if;
  select w.company_id into v_company from public.workers w where w.id=p_worker_id;
  if v_company is null then raise exception '社員を確認できません'; end if;
  select exists(select 1 from public.worker_personnel_profiles p
                where p.worker_id=p_worker_id) into v_existing;
  v_current:=private.worker_personnel_payload(p_worker_id);
  if not v_existing then
    perform private.apply_worker_personnel_payload(p_worker_id,p_payload,v_actor);
    return jsonb_build_object('status','saved','requires_approval',false);
  end if;
  if v_current=p_payload then
    return jsonb_build_object('status','unchanged','requires_approval',false);
  end if;
  select count(*)::integer into v_required
  from public.worker_personnel_approvers a
  where a.company_id=v_company and a.user_id<>v_actor;
  if v_required<1 then
    raise exception '社員個人情報の承認者を1〜3名で設定してください（申請者本人は承認できません）';
  end if;
  v_required:=least(v_required,3);
  update public.worker_personnel_change_requests
  set status='rejected',resolved_at=now()
  where worker_id=p_worker_id and requested_by=v_actor and status='pending';
  insert into public.worker_personnel_change_requests(
    company_id,worker_id,requested_by,proposed,required_approvals
  ) values(v_company,p_worker_id,v_actor,p_payload,v_required)
  returning id into v_request;
  insert into public.app_notifications(
    company_id,recipient_user_id,kind,title,body,action_key,action_id
  )
  select v_company,a.user_id,'approval','社員個人情報の変更申請',
    '社員個人情報の変更申請があります。登録済み承認者の承認後に反映されます。',
    'worker_personnel_change',v_request
  from public.worker_personnel_approvers a
  where a.company_id=v_company and a.user_id<>v_actor;
  return jsonb_build_object(
    'status','pending','requires_approval',true,
    'request_id',v_request,'required_approvals',v_required
  );
end
$$;

create or replace function public.pending_worker_personnel_changes()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',r.id,'worker_id',r.worker_id,'worker_name',w.name,
      'requested_by',r.requested_by,'proposed',r.proposed,
      'created_at',r.created_at,'required_approvals',r.required_approvals,
      'approval_count',(
        select count(*) from public.worker_personnel_change_approvals a
        where a.request_id=r.id and a.decision='approve'
      )
    ) order by r.created_at)
    from public.worker_personnel_change_requests r
    join public.workers w on w.id=r.worker_id
    where r.status='pending'
      and private.is_worker_personnel_approver(r.company_id)
      and r.requested_by<>v_user
  ),'[]'::jsonb);
end
$$;

create or replace function public.decide_worker_personnel_change(
  p_request_id uuid,p_approve boolean
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_req public.worker_personnel_change_requests%rowtype;
  v_count integer; v_required integer;
begin
  select * into v_req from public.worker_personnel_change_requests
  where id=p_request_id for update;
  if not found or v_req.status<>'pending' then
    raise exception '変更申請を確認できません';
  end if;
  if v_req.requested_by=v_user then raise exception '自分の申請は承認できません'; end if;
  if not private.is_worker_personnel_approver(v_req.company_id) then
    raise exception '承認権限がありません';
  end if;
  insert into public.worker_personnel_change_approvals(
    request_id,approver_user_id,decision
  ) values(
    p_request_id,v_user,case when p_approve then 'approve' else 'reject' end
  ) on conflict(request_id,approver_user_id) do nothing;
  if not p_approve then
    update public.worker_personnel_change_requests
    set status='rejected',resolved_at=now() where id=p_request_id;
    return jsonb_build_object('status','rejected');
  end if;
  select count(*) into v_count
  from public.worker_personnel_change_approvals a
  where a.request_id=p_request_id and a.decision='approve';
  v_required:=greatest(1,least(coalesce(v_req.required_approvals,1),3));
  if v_count>=v_required then
    perform private.apply_worker_personnel_payload(
      v_req.worker_id,v_req.proposed,v_user
    );
    update public.worker_personnel_change_requests
    set status='approved',resolved_at=now() where id=p_request_id;
    insert into public.app_notifications(
      company_id,recipient_user_id,kind,title,body,action_key,action_id
    ) values(
      v_req.company_id,v_req.requested_by,'approval',
      '社員個人情報の変更が承認されました',
      format('%s名の承認が完了し、社員個人情報へ反映されました。',v_required),
      'worker_personnel_change_completed',p_request_id
    );
    return jsonb_build_object(
      'status','approved','approval_count',v_count,
      'required_approvals',v_required
    );
  end if;
  return jsonb_build_object(
    'status','pending','approval_count',v_count,
    'required_approvals',v_required
  );
end
$$;

revoke execute on function public.worker_personnel_approver_rows()
  from public,anon;
revoke execute on function public.set_worker_personnel_approvers(uuid[])
  from public,anon;
grant execute on function public.worker_personnel_approver_rows()
  to authenticated;
grant execute on function public.set_worker_personnel_approvers(uuid[])
  to authenticated;
