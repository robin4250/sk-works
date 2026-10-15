-- Draft only: no auth hook is changed. Registration attribution is deliberately
-- unavailable to clients until independently verified onboarding is connected.
create table private.app_referral_settings (
 id boolean primary key default true check(id), enabled boolean not null default false,
 public_enabled boolean not null default false, notify_master boolean not null default true,
 distribution_url text not null default '', updated_at timestamptz not null default now()
);
insert into private.app_referral_settings(id) values(true);
create table private.app_referral_invitations (
 id uuid primary key default gen_random_uuid(), inviter_id uuid not null references auth.users(id),
 company_id uuid not null references public.companies(id), recipient_name text not null,
 recipient_phone text not null, created_at timestamptz not null default clock_timestamp(),
 composer_opened_at timestamptz, registered_user_id uuid unique references auth.users(id),
 registered_at timestamptz, points integer check(points is null or points>=0),
 check((registered_user_id is null)=(registered_at is null))
);
create index app_referral_owner_history on private.app_referral_invitations(inviter_id,created_at desc);
create index app_referral_recipient_history on private.app_referral_invitations(recipient_phone,created_at desc,id);
alter table private.app_referral_settings enable row level security;
alter table private.app_referral_invitations enable row level security;
revoke all on private.app_referral_settings,private.app_referral_invitations from public,anon,authenticated;

create function private.app_referral_dispatch(p_action text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); c uuid; admin boolean; master boolean;
 s private.app_referral_settings%rowtype; r private.app_referral_invitations%rowtype;
 phone text; url text; rows jsonb; ranks jsonb;
begin
 if u is null or not private.account_access_allowed() then raise exception 'access denied' using errcode='42501'; end if;
 master:=public.is_current_user_master_admin();
 select cm.company_id,cm.role::text in ('owner','admin') into c,admin
 from public.company_members cm where cm.user_id=u order by cm.company_id limit 1;
 if c is null and not master then raise exception 'company membership required' using errcode='42501'; end if;
 select * into s from private.app_referral_settings where id;
 if p_action='settings' then
   if not master then raise exception 'master administrator required' using errcode='42501'; end if;
   url:=trim(coalesce(p_args->>'url',''));
   if url<>'' and url !~ '^https://(testflight\.apple\.com/join/[A-Za-z0-9]+|apps\.apple\.com/[^[:space:]]+)$' then raise exception 'invalid distribution URL'; end if;
   update private.app_referral_settings set enabled=(p_args->>'enabled')::boolean,
   public_enabled=(p_args->>'public_enabled')::boolean,notify_master=(p_args->>'notify_master')::boolean,
   distribution_url=url,updated_at=clock_timestamp() where id;
   return '{}'::jsonb;
 end if;
 if p_action='prepare' then
   if not s.enabled or not (coalesce(admin,false) or master or s.public_enabled) then raise exception 'invitation disabled' using errcode='42501'; end if;
   if s.distribution_url='' then raise exception 'distribution URL not configured'; end if;
   phone:=regexp_replace(coalesce(p_args->>'phone',''),'[[:space:]()-]','','g');
   if phone like '+81%' then phone:='0'||substr(phone,4); end if;
   if phone !~ '^0[0-9]{9,10}$' or length(trim(coalesce(p_args->>'name',''))) not between 1 and 100 then raise exception 'invalid name or phone'; end if;
   if c is null then raise exception 'company membership required'; end if;
   -- Do not infer existing registration from an unverified profile phone.
   insert into private.app_referral_invitations(inviter_id,company_id,recipient_name,recipient_phone)
   values(u,c,trim(p_args->>'name'),phone) returning * into r;
   return jsonb_build_object('id',r.id,'phone',phone,'message',r.recipient_name||' 様'||E'\nSKOアプリへのご招待です。'||E'\n'||s.distribution_url||E'\n招待番号: '||r.id::text);
 end if;
 if p_action='opened' then
   if not s.enabled or not (coalesce(admin,false) or master or s.public_enabled) then raise exception 'invitation disabled' using errcode='42501'; end if;
   update private.app_referral_invitations set composer_opened_at=coalesce(composer_opened_at,clock_timestamp())
   where id=(p_args->>'id')::uuid and inviter_id=u;
   if not found then raise exception 'invitation unavailable' using errcode='42501'; end if;
   return '{}'::jsonb;
 end if;
 if p_action not in ('snapshot','master') then raise exception 'unsupported action'; end if;
 if p_action='master' and not master then raise exception 'master administrator required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into rows from (
   select i.id,i.inviter_id,i.company_id,coalesce(p.display_name,'名前未登録') inviter_name,
   coalesce(cmp.name,'会社名未登録') company_name,i.recipient_name,i.recipient_phone,i.created_at,i.registered_user_id,i.registered_at,i.points,
   case when i.registered_at is not null then '登録確認済み' when i.composer_opened_at is not null then 'SMS作成画面を開いた（送信・配達未確認）' else '招待を準備（未送信）' end state_label
   from private.app_referral_invitations i left join public.user_profiles p on p.user_id=i.inviter_id
   left join public.companies cmp on cmp.id=i.company_id
   where (p_action='master' or i.inviter_id=u) order by i.created_at desc limit 500
 ) x;
 if p_action='master' then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.registration_count desc,x.name),'[]'::jsonb) into ranks from (
     select i.inviter_id,coalesce(p.display_name,'名前未登録') name,coalesce(cmp.name,'会社名未登録') company_name,
     count(i.registered_user_id) registration_count,sum(i.points) points
     from private.app_referral_invitations i left join public.user_profiles p on p.user_id=i.inviter_id
     left join public.companies cmp on cmp.id=i.company_id group by i.inviter_id,p.display_name,cmp.name
   ) x;
 end if;
 return jsonb_build_object('enabled',s.enabled,'public_enabled',s.public_enabled,'notify_master',s.notify_master,
 'can_invite',s.enabled and (coalesce(admin,false) or master or s.public_enabled),
 'distribution_url_ready',s.distribution_url<>'','distribution_url',case when master then s.distribution_url else '' end,
 'invitations',rows,'rankings',coalesce(ranks,'[]'::jsonb),'attribution_connected',false);
end $$;
revoke all on function private.app_referral_dispatch(text,jsonb) from public,anon;
grant execute on function private.app_referral_dispatch(text,jsonb) to authenticated;
grant usage on schema private to authenticated;

create function public.app_referral_snapshot() returns jsonb language sql security invoker set search_path='' as $$ select private.app_referral_dispatch('snapshot') $$;
create function public.app_referral_master_snapshot() returns jsonb language sql security invoker set search_path='' as $$ select private.app_referral_dispatch('master') $$;
create function public.app_referral_prepare(p_name text,p_phone text) returns jsonb language sql security invoker set search_path='' as $$ select private.app_referral_dispatch('prepare',jsonb_build_object('name',p_name,'phone',p_phone)) $$;
create function public.app_referral_composer_opened(p_invitation_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.app_referral_dispatch('opened',jsonb_build_object('id',p_invitation_id)) $$;
create function public.app_referral_save_settings(p_enabled boolean,p_public_enabled boolean,p_notify_master boolean,p_distribution_url text) returns jsonb language sql security invoker set search_path='' as $$ select private.app_referral_dispatch('settings',jsonb_build_object('enabled',p_enabled,'public_enabled',p_public_enabled,'notify_master',p_notify_master,'url',p_distribution_url)) $$;
revoke all on function public.app_referral_snapshot(),public.app_referral_master_snapshot(),public.app_referral_prepare(text,text),public.app_referral_composer_opened(uuid),public.app_referral_save_settings(boolean,boolean,boolean,text) from public,anon;
grant execute on function public.app_referral_snapshot(),public.app_referral_master_snapshot(),public.app_referral_prepare(text,text),public.app_referral_composer_opened(uuid),public.app_referral_save_settings(boolean,boolean,boolean,text) to authenticated;
