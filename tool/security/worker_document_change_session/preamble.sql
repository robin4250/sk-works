-- REVIEW ONLY: new module only; no shared function replacement; no production apply.
do $pin$ declare p record;begin
 for p in select * from (values
 ('private.require_reauthentication_session()','165d0f26da6f6e346bb2766ae70282f7','{postgres=X/postgres}','search_path=""'),
 ('private.has_company_feature(uuid,text)','e669fb9e3fe1af2b73eee1745703b272',null,'search_path=public, private, pg_temp'),
 ('private.account_access_allowed()','313d371759a4de968cfe99db050ee65d','{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}','search_path=""')
 ) v(signature,hash,acl,config) loop
 if not exists(select 1 from pg_proc f where f.oid=to_regprocedure(p.signature)
  and md5(pg_get_functiondef(f.oid))=p.hash and f.prosecdef
  and pg_get_userbyid(f.proowner)='postgres' and f.proacl::text is not distinct from p.acl
  and f.proconfig=array[p.config]) then
  raise sqlstate '55000' using message='Document prerequisite definition/attributes changed';end if;
 end loop;
 if to_regclass('private.worker_document_change_rollout') is not null then raise sqlstate '55000' using message='Inspect existing module';end if;
end $pin$;
create table private.worker_document_change_rollout(enabled boolean not null default false,singleton boolean primary key default true check(singleton));
insert into private.worker_document_change_rollout values(false,true);
create table private.worker_document_change_events(event_id bigint generated always as identity primary key,request_id uuid not null,actor_id uuid not null,session_id uuid not null,action text not null,created_at timestamptz not null default clock_timestamp());
create table private.worker_document_change_installation(singleton boolean primary key default true check(singleton),catalog jsonb not null);
alter table private.worker_document_change_rollout enable row level security;
alter table private.worker_document_change_events enable row level security;
alter table private.worker_document_change_installation enable row level security;
revoke all on private.worker_document_change_rollout,private.worker_document_change_events,private.worker_document_change_installation from public,anon,authenticated,service_role;
revoke all on sequence private.worker_document_change_events_event_id_seq from public,anon,authenticated,service_role;
create function private.worker_document_change_enabled() returns boolean language sql volatile security definer set search_path='' as $$select coalesce((select enabled from private.worker_document_change_rollout where singleton for share),false)$$;
revoke all on function private.worker_document_change_enabled() from public,anon,authenticated,service_role;
