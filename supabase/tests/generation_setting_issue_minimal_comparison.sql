-- Rejected minimal NULL-only fix for regression comparison, not deployable.
CREATE OR REPLACE FUNCTION private.upsert_generation_setting_issue(cid uuid, p_issue_key text, p_issue_type text, p_title text, p_body text, p_action_key text DEFAULT NULL::text, p_action_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if not coalesce(existed,false) or existing_resolved is not null then
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
