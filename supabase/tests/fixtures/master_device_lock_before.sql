CREATE OR REPLACE FUNCTION public.set_master_device_locked(p_device_id uuid, p_locked boolean)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 v_actor uuid := auth.uid();
 v_device private.master_devices%rowtype;
begin
 if not public.is_current_user_master_admin() then raise exception 'master admin permission required'; end if;
 select * into v_device from private.master_devices where id=p_device_id and master_user_id=v_actor for update;
 if not found then raise exception 'master device not found'; end if;
 if v_device.revoked_at is not null then raise exception 'revoked master device cannot be changed'; end if;
 update private.master_devices set is_locked=p_locked where id=p_device_id;
 insert into private.master_admin_audit_log(actor_user_id,action,target_user_id,details)
 values(v_actor,case when p_locked then 'master_device_lock' else 'master_device_unlock' end,v_actor,
  jsonb_build_object('device_id',p_device_id,'device_name',v_device.device_name));
end;
$function$;
