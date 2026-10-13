-- Read-only staged settings; neither enables notifications nor changes roles.
create function private.get_vehicle_notification_settings(p_vehicle_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid; ids uuid[]; candidates jsonb; configured boolean;
begin
 if auth.uid() is null or not private.account_access_allowed() then
  raise exception 'account unavailable' using errcode='42501';
 end if;
 select company_id into c from public.vehicles where id=p_vehicle_id;
 if c is null or not exists(select 1 from public.company_members
  where company_id=c and user_id=auth.uid() and role::text in ('owner','admin')) then
  raise exception 'vehicle administrator required' using errcode='42501';
 end if;
 select user_ids into ids from private.vehicle_notification_assignees where vehicle_id=p_vehicle_id and company_id=c;
 configured:=found;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role::text,
  'name',coalesce(w.name,case when m.role::text='owner' then '会社管理者' else '管理者' end)) order by m.user_id),'[]'::jsonb)
 into candidates from public.company_members m
 left join lateral(select name from public.workers where company_id=c and user_id=m.user_id and status='active' order by id limit 1)w on true
 where m.company_id=c and (w.name is not null or (m.role::text in ('owner','admin') and not exists(select 1 from public.workers where company_id=c and user_id=m.user_id)));
 return jsonb_build_object('vehicle_id',p_vehicle_id,'company_id',c,'can_manage',true,
  'enabled',coalesce((select enabled from private.source_notification_rollouts where company_id=c),false),
  'configured',configured,'user_ids',coalesce(to_jsonb(ids),'[]'::jsonb),
  'suggested_user_ids',case when not configured and candidates @> jsonb_build_array(jsonb_build_object('user_id',auth.uid())) then jsonb_build_array(auth.uid()) else '[]'::jsonb end,
  'candidates',candidates);
end $$;
create function public.get_vehicle_notification_settings(p_vehicle_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select private.get_vehicle_notification_settings(p_vehicle_id)
$$;
revoke all on function private.get_vehicle_notification_settings(uuid),public.get_vehicle_notification_settings(uuid) from public,anon;
grant execute on function private.get_vehicle_notification_settings(uuid),public.get_vehicle_notification_settings(uuid) to authenticated;
