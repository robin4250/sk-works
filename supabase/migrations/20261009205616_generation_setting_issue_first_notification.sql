-- Source only; no production application. Retains existing function ACL and lock order.
do $guard$
begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.upsert_generation_setting_issue(uuid,text,text,text,text,text,uuid)') and md5(prosrc)='1c0e6becf30f98e0e829b034767a4d0e' and prosecdef and proconfig=array['search_path=""']) then
  raise exception 'generation setting issue source prerequisite differs';
 end if;
end $guard$;
CREATE OR REPLACE FUNCTION private.upsert_generation_setting_issue(cid uuid, p_issue_key text, p_issue_type text, p_title text, p_body text, p_action_key text DEFAULT NULL::text, p_action_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  existing_resolved timestamptz;
  inserted boolean:=false;
  should_notify boolean:=false;
  member record;
begin
  insert into public.generation_setting_issues(
    company_id,issue_key,issue_type,title,body,action_key,action_id,resolved_at,updated_at
  )
  values(cid,p_issue_key,p_issue_type,p_title,p_body,p_action_key,p_action_id,null,now())
  on conflict(company_id,issue_key) do nothing
  returning true into inserted;

  if coalesce(inserted,false) then
    should_notify:=true;
  else
    select resolved_at into existing_resolved
    from public.generation_setting_issues
    where company_id=cid and issue_key=p_issue_key
    for update;
    if not found then raise exception 'generation setting issue disappeared' using errcode='40001'; end if;
    should_notify:=existing_resolved is not null;
    update public.generation_setting_issues
    set issue_type=p_issue_type,title=p_title,body=p_body,
        action_key=p_action_key,action_id=p_action_id,resolved_at=null,updated_at=now()
    where company_id=cid and issue_key=p_issue_key;
  end if;

  if should_notify then
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
$function$
;
