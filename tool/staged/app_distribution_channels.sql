-- Staged candidate only. No production apply or rollout.
-- Keep legacy settings/RPCs, invitation ownership and unawarded points intact.
alter table private.app_referral_settings
  add column testflight_url text not null default '',
  add column web_url text not null default '',
  add column public_guide_url text not null default '';
alter table private.app_referral_invitations
  add column distribution_channel text check(distribution_channel in ('testflight','web','public')),
  add column invitation_kind text check(invitation_kind in ('app','company','employee','friend')),
  add column distribution_url_snapshot text;

create function private.app_distribution_dispatch(p_action text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); c uuid; state jsonb; s private.app_referral_settings%rowtype;
 r private.app_referral_invitations%rowtype; channel text; kind text; phone text;
 tf text; web text; guide text; url text; entry record; history jsonb;
begin
 -- Existing dispatch owns active-account, membership, Master and invite gates.
 state:=private.app_referral_dispatch(case when p_action='settings' or
   (p_action='snapshot' and coalesce((p_args->>'master')::boolean,false))
   then 'master' else 'snapshot' end);
 select * into s from private.app_referral_settings where id;
 if p_action='settings' then
   tf:=trim(coalesce(p_args->>'testflight',''));
   web:=trim(coalesce(p_args->>'web',''));
   guide:=trim(coalesce(p_args->>'public',''));
   if length(tf)>2048 or tf<>'' and tf !~ '^https://testflight\.apple\.com/join/[A-Za-z0-9]+$' then
     raise exception 'invalid TestFlight URL'; end if;
   foreach url in array array[web,guide] loop
     if url<>'' and (length(url)>2048 or
       url !~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}(/[[:graph:]]*)?$'
       or url ~ '[[:space:]@\\]') then raise exception 'invalid HTTPS guide URL'; end if;
   end loop;
   update private.app_referral_settings set testflight_url=tf,web_url=web,
     public_guide_url=guide,
     distribution_url=case when distribution_url ~ '^https://testflight\.apple\.com/join/' then tf else distribution_url end,
     updated_at=clock_timestamp() where id;
   return '{}'::jsonb;
 end if;
 tf:=case when s.testflight_url<>'' then s.testflight_url
   when s.distribution_url ~ '^https://testflight\.apple\.com/join/[A-Za-z0-9]+$'
   then s.distribution_url else '' end;
 web:=s.web_url; guide:=s.public_guide_url;
 if p_action='snapshot' then
   select coalesce(jsonb_agg(item.value || jsonb_build_object(
     'distribution_channel',i.distribution_channel,
     'invitation_kind',i.invitation_kind,
     'distribution_label',case i.distribution_channel when 'testflight' then 'TestFlight版'
       when 'web' then 'WEB版' when 'public' then '公開版の案内' else '従来の配布URL' end)
     order by item.ordinality),'[]'::jsonb)
   into history from jsonb_array_elements(state->'invitations') with ordinality item(value,ordinality)
     join private.app_referral_invitations i on i.id=(item.value->>'id')::uuid;
   return state || jsonb_build_object('distribution_url_ready',tf<>'' or web<>'' or (guide<>'' and s.public_enabled),
     'distribution_channels',jsonb_build_array(
     jsonb_build_object('key','testflight','label','TestFlight版','ready',tf<>''),
     jsonb_build_object('key','web','label','WEB版','ready',web<>''),
     jsonb_build_object('key','public','label','公開版の案内','ready',guide<>'' and s.public_enabled)),
     'distribution_links',case when coalesce((p_args->>'master')::boolean,false)
       then jsonb_build_object('testflight',tf,'web',web,'public',guide)
       else '{}'::jsonb end,
     'invitations',history);
 end if;
 if p_action<>'prepare' then raise exception 'unsupported action'; end if;
 if coalesce((state->>'can_invite')::boolean,false) is not true then
   raise exception 'invitation disabled' using errcode='42501'; end if;
 channel:=p_args->>'channel'; kind:=p_args->>'kind';
 if channel is null or channel not in ('testflight','web','public') or
    kind is null or kind not in ('app','company','employee','friend') then
   raise exception 'invalid channel or invitation kind'; end if;
 if kind='friend' and channel<>'public' then raise exception 'friend invitations require public guide'; end if;
 if channel='public' and not s.public_enabled then
   raise exception 'public distribution disabled' using errcode='42501'; end if;
 url:=case channel when 'testflight' then tf when 'web' then web when 'public' then guide end;
 if coalesce(url,'')='' then raise exception 'distribution URL not configured'; end if;
 phone:=regexp_replace(coalesce(p_args->>'phone',''),'[[:space:]()-]','','g');
 if phone like '+81%' then phone:='0'||substr(phone,4); end if;
 if phone !~ '^0[0-9]{9,10}$' or length(trim(coalesce(p_args->>'name',''))) not between 1 and 100 then
   raise exception 'invalid name or phone'; end if;
 select cm.company_id into c from public.company_members cm
   where cm.user_id=u order by cm.company_id limit 1;
 if c is null then raise exception 'company membership required' using errcode='42501'; end if;
 insert into private.app_referral_invitations(inviter_id,company_id,recipient_name,
   recipient_phone,source,distribution_channel,invitation_kind,distribution_url_snapshot)
 values(u,c,trim(p_args->>'name'),phone,case when kind='friend' then 'friend_add' else 'app_invite' end,
   channel,kind,url) returning * into r;
 return jsonb_build_object('id',r.id,'phone',phone,'channel',channel,'kind',kind,
   'message',r.recipient_name||' 様'||E'\nSKOアプリのご案内です。\n'||
   case channel when 'testflight' then 'TestFlight版' when 'web' then 'WEB版' else '公開版の案内' end||
   E'\n'||url||E'\n招待番号: '||r.id::text);
end $$;
revoke all on function private.app_distribution_dispatch(text,jsonb) from public,anon;
grant execute on function private.app_distribution_dispatch(text,jsonb) to authenticated;

create function public.app_distribution_snapshot(p_master boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
 select private.app_distribution_dispatch('snapshot',jsonb_build_object('master',p_master)) $$;
create function public.app_distribution_save_links(p_testflight_url text,p_web_url text,p_public_url text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.app_distribution_dispatch('settings',jsonb_build_object(
   'testflight',p_testflight_url,'web',p_web_url,'public',p_public_url)) $$;
create function public.app_distribution_prepare(p_name text,p_phone text,p_channel text,p_kind text default 'app')
returns jsonb language sql security invoker set search_path='' as $$
 select private.app_distribution_dispatch('prepare',jsonb_build_object(
   'name',p_name,'phone',p_phone,'channel',p_channel,'kind',p_kind)) $$;
revoke all on function public.app_distribution_snapshot(boolean),
 public.app_distribution_save_links(text,text,text),public.app_distribution_prepare(text,text,text,text) from public,anon;
grant execute on function public.app_distribution_snapshot(boolean),
 public.app_distribution_save_links(text,text,text),public.app_distribution_prepare(text,text,text,text) to authenticated;
