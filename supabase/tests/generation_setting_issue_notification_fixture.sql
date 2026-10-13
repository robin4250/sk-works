-- Disposable synthetic IDs and exact captured sink/function definitions.
create schema private;create schema auth;create role anon;create role authenticated;create table auth.users(id uuid primary key);create table public.companies(id uuid primary key);create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.app_notifications(id uuid not null default gen_random_uuid(),company_id uuid not null,recipient_user_id uuid not null,kind text not null default 'info'::text,title text not null,body text,action_key text,action_id uuid,read_at timestamp with time zone,created_at timestamp with time zone not null default now());
create table public.generation_setting_issues(id uuid not null default gen_random_uuid(),company_id uuid not null,issue_key text not null,issue_type text not null,title text not null,body text not null,action_key text,action_id uuid,resolved_at timestamp with time zone,created_at timestamp with time zone not null default now(),updated_at timestamp with time zone not null default now());
alter table public.app_notifications add constraint app_notifications_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.app_notifications add constraint app_notifications_pkey PRIMARY KEY (id);
alter table public.app_notifications add constraint app_notifications_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.generation_setting_issues add constraint generation_setting_issues_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.generation_setting_issues add constraint generation_setting_issues_company_id_issue_key_key UNIQUE (company_id, issue_key);
alter table public.generation_setting_issues add constraint generation_setting_issues_pkey PRIMARY KEY (id);
CREATE OR REPLACE FUNCTION private.enqueue_notification(p_company_id uuid, p_recipient_user_id uuid, p_kind text, p_title text, p_body text DEFAULT NULL::text, p_action_key text DEFAULT NULL::text, p_action_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_id uuid;
begin
  insert into public.app_notifications(
    company_id,
    recipient_user_id,
    kind,
    title,
    body,
    action_key,
    action_id
  )
  values(
    p_company_id,
    p_recipient_user_id,
    coalesce(nullif(trim(p_kind), ''), 'info'),
    p_title,
    p_body,
    p_action_key,
    p_action_id
  )
  returning id into v_id;

  return v_id;
end;
$function$
;
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
$function$
;
insert into public.companies values('10000000-0000-0000-0000-000000000001');insert into auth.users values('00000000-0000-0000-0000-000000000001');insert into public.company_members values('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner');
