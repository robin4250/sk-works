-- Contact profile proposals are independent of contract prices and payroll.
create table private.company_profile_review_settings(company_id uuid primary key references public.companies(id),enabled boolean not null default false);
create table private.company_profile_revisions(
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),
 old_value jsonb not null,new_value jsonb not null,changed_by uuid,created_at timestamptz not null default now()
);
create table private.company_profile_reviews(
 id uuid primary key default gen_random_uuid(),revision_id uuid not null references private.company_profile_revisions(id),
 company_id uuid not null references public.companies(id),trade_company_id uuid not null references public.trade_companies(id),
 old_value jsonb not null,status text not null default 'pending' check(status in('pending','accepted','dismissed')),
 reviewed_by uuid,reviewed_at timestamptz,unique(revision_id,trade_company_id)
);
alter table private.company_profile_review_settings enable row level security;
alter table private.company_profile_revisions enable row level security;
alter table private.company_profile_reviews enable row level security;
revoke all on private.company_profile_review_settings,private.company_profile_revisions,private.company_profile_reviews from public,anon,authenticated;

create function private.company_contact_value(p_value jsonb) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('name',p_value->'name','address',p_value->'address','phone',p_value->'phone','email',p_value->'email','corporate_number',p_value->'corporate_number')
$$;
revoke all on function private.company_contact_value(jsonb) from public,anon,authenticated;
create function private.capture_company_profile_revision() returns trigger language plpgsql security definer set search_path='' as $$
declare oldv jsonb:=private.company_contact_value(to_jsonb(old));newv jsonb:=private.company_contact_value(to_jsonb(new));rid uuid;review_id uuid;rec record;
begin
 if oldv=newv then return new;end if;
 insert into private.company_profile_revisions(company_id,old_value,new_value,changed_by) values(new.id,oldv,newv,auth.uid()) returning id into rid;
 if not coalesce((select enabled from private.company_profile_review_settings where company_id=new.id),false) then return new;end if;
 for rec in select t.id,t.company_id,private.company_contact_value(to_jsonb(t)) value from public.trade_companies t
  join private.company_profile_review_settings s on s.company_id=t.company_id and s.enabled
  where t.linked_company_id=new.id and t.link_status='linked'
 loop
  insert into private.company_profile_reviews(revision_id,company_id,trade_company_id,old_value)
  values(rid,rec.company_id,rec.id,rec.value) returning id into review_id;
  insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)
  select rec.company_id,m.user_id,'company_profile_review','連携先の会社情報が更新されました',
  '情報が更新されたみたいなので、更新しますか？旧登録情報はそのまま記録に残ります。','company_profile_review',review_id
  from public.company_members m where m.company_id=rec.company_id and m.role::text in('owner','admin');
 end loop;
 return new;
end $$;
revoke all on function private.capture_company_profile_revision() from public,anon,authenticated;
create trigger company_contact_revision after update of name,address,phone,email,corporate_number on public.companies for each row execute function private.capture_company_profile_revision();

create function private.company_profile_review_workspace() returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_company_admin_id();
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます';end if;
 return jsonb_build_object('enabled',coalesce((select enabled from private.company_profile_review_settings where company_id=cid),false),
 'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'trade_company_id',r.trade_company_id,'source_company_id',v.company_id,
 'old',r.old_value,'proposed',v.new_value,'source_old',v.old_value,'created_at',v.created_at,'status',r.status,'reviewed_at',r.reviewed_at) order by v.created_at desc)
 from private.company_profile_reviews r join private.company_profile_revisions v on v.id=r.revision_id where r.company_id=cid),'[]'::jsonb));
end $$;
create function private.set_company_profile_review_enabled(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_company_admin_id();
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます';end if;
 insert into private.company_profile_review_settings values(cid,p_enabled) on conflict(company_id) do update set enabled=excluded.enabled;
end $$;
create function private.respond_company_profile_review(p_review_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_company_admin_id();r private.company_profile_reviews%rowtype;v private.company_profile_revisions%rowtype;t public.trade_companies%rowtype;
begin
 if auth.uid() is null or cid is null then raise exception '管理者のみ操作できます';end if;
 if not coalesce((select enabled from private.company_profile_review_settings where company_id=cid),false) then raise exception '会社情報更新確認は停止中です';end if;
 select * into r from private.company_profile_reviews where id=p_review_id and company_id=cid for update;
 if r.id is null or r.status<>'pending' then raise exception '確認対象が見つからないか処理済みです';end if;
 select * into strict v from private.company_profile_revisions where id=r.revision_id;
 select * into t from public.trade_companies where id=r.trade_company_id and company_id=cid for update;
 if t.id is null or t.linked_company_id is distinct from v.company_id or t.link_status<>'linked' then raise exception '会社連携が変更されています';end if;
 if p_accept then
  if (select private.company_contact_value(to_jsonb(c)) from public.companies c where c.id=v.company_id) is distinct from v.new_value then raise exception 'さらに新しい会社情報があります。最新の通知を確認してください';end if;
  if private.company_contact_value(to_jsonb(t))<>r.old_value then raise exception '登録情報が変更されています。更新候補を再確認してください';end if;
  update public.trade_companies set name=v.new_value->>'name',address=v.new_value->>'address',phone=v.new_value->>'phone',
   email=v.new_value->>'email',corporate_number=v.new_value->>'corporate_number',updated_by=auth.uid(),updated_at=now() where id=t.id;
 end if;
 update private.company_profile_reviews set status=case when p_accept then 'accepted' else 'dismissed' end,reviewed_by=auth.uid(),reviewed_at=now() where id=r.id;
end $$;
revoke all on function private.company_profile_review_workspace(),private.set_company_profile_review_enabled(boolean),private.respond_company_profile_review(uuid,boolean) from public,anon,authenticated;
create function public.company_profile_review_workspace() returns jsonb language sql security invoker set search_path='' as $$select private.company_profile_review_workspace()$$;
create function public.set_company_profile_review_enabled(p_enabled boolean) returns void language sql security invoker set search_path='' as $$select private.set_company_profile_review_enabled(p_enabled)$$;
create function public.respond_company_profile_review(p_review_id uuid,p_accept boolean) returns void language sql security invoker set search_path='' as $$select private.respond_company_profile_review(p_review_id,p_accept)$$;
revoke all on function public.company_profile_review_workspace(),public.set_company_profile_review_enabled(boolean),public.respond_company_profile_review(uuid,boolean) from public,anon;
grant execute on function private.company_profile_review_workspace(),private.set_company_profile_review_enabled(boolean),private.respond_company_profile_review(uuid,boolean),public.company_profile_review_workspace(),public.set_company_profile_review_enabled(boolean),public.respond_company_profile_review(uuid,boolean) to authenticated;
